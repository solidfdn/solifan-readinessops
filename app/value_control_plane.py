"""Foundation Slice 1 — Value Control Plane module.

Exposes render_value_control_plane(session, assessment_run_id, actor) which
renders the complete Decision Pack workspace: AI Initiative, retained TXT/PDF
evidence, Draft Decision Pack review, Published Governed Records, AI Portfolio.
"""

import hashlib
import io
import json
from datetime import datetime
from uuid import uuid4

import pandas as pd
import streamlit as st


# -- Helpers ------------------------------------------------------------------

def _text(value, fallback="\u2014"):
    if value is None:
        return fallback
    rendered = str(value).strip()
    if not rendered or rendered.lower() in {"nan", "none", "null", "nat"}:
        return fallback
    return rendered


def _escaped(value, fallback="\u2014"):
    import html as _html
    return _html.escape(_text(value, fallback))


def _integer(value, fallback=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def _timestamp(value):
    if value is None:
        return "\u2014"
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M")
    return _text(value)[:16]


def _badge(label, tone="neutral"):
    css = {
        "high": "badge badge-high", "medium": "badge badge-medium",
        "low": "badge badge-low", "success": "badge badge-success",
        "warning": "badge badge-warning", "danger": "badge badge-danger",
        "info": "badge badge-info", "neutral": "badge badge-neutral",
    }.get(tone, "badge badge-neutral")
    import html as _html
    return f'<span class="{css}">{_html.escape(str(label))}</span>'


def _query(session, sql, params=None):
    return session.sql(sql, params=params).to_pandas()


def _execute(session, sql, params=None):
    return session.sql(sql, params=params).collect()


def _call_json(session, sql, params=None):
    result = session.sql(sql, params=params).collect()
    if not result:
        return {"status": "FAILED", "error": "No result"}
    raw = result[0][0]
    if isinstance(raw, dict):
        return raw
    try:
        return json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        return {"status": "FAILED", "error": f"Unexpected: {raw}"}


def _rerun():
    if hasattr(st, "rerun"):
        st.rerun()
    else:
        st.experimental_rerun()


def _show_df(df):
    d = df.copy()
    d.index = range(1, len(d) + 1)
    d.index.name = "No."
    st.dataframe(d, use_container_width=True)


def _origin_badge(status):
    if status == "REVIEW_REQUIRED":
        return _badge("AI Draft", "warning")
    if status == "APPROVED":
        return _badge("Human Reviewed", "success")
    if status == "REJECTED":
        return _badge("Rejected", "danger")
    if status == "PUBLISHED":
        return _badge("Published Governed Record", "info")
    return _badge(status, "neutral")


# -- Section renderers --------------------------------------------------------

def _render_initiative(session, run_id, selected_run):
    st.subheader("AI Initiative")
    try:
        init_df = _query(session,
            "SELECT INITIATIVE_ID, INITIATIVE_NAME, LIFECYCLE_STAGE, STATUS "
            "FROM AI_INITIATIVE WHERE STATUS = 'ACTIVE' ORDER BY INITIATIVE_NAME")
    except Exception:
        init_df = pd.DataFrame()

    tab_select, tab_create = st.tabs(["Select existing", "Create new"])

    with tab_select:
        if init_df.empty:
            st.info("No active initiatives. Create one in the next tab.")
        else:
            opts = {
                f"{_text(r['INITIATIVE_NAME'])} ({_text(r['LIFECYCLE_STAGE'])})": _text(r["INITIATIVE_ID"])
                for _, r in init_df.iterrows()
            }
            sel = st.selectbox("Initiative", list(opts.keys()), key="vcp_sel_init")
            sel_id = opts[sel]
            current_id = _text(selected_run.get("INITIATIVE_ID", ""), "")
            if current_id != sel_id:
                if st.button("Link to assessment", key="vcp_link_init"):
                    _execute(
                        session,
                        "UPDATE ASSESSMENT_RUNS SET INITIATIVE_ID = ? WHERE RUN_ID = ?",
                        [sel_id, run_id],
                    )
                    st.session_state["vcp_msg"] = "Initiative linked."
                    _rerun()
            else:
                st.success(f"Linked: {sel}")

    with tab_create:
        name = st.text_input("Name", key="vcp_init_name")
        desc = st.text_area("Description", key="vcp_init_desc", height=60)
        owner = st.text_input("Owner", key="vcp_init_owner")
        stage = st.selectbox("Stage", ["IDEATION", "PILOT", "PRODUCTION"], key="vcp_init_stage")
        outcome = st.text_input("Business outcome", key="vcp_init_outcome")
        if st.button("Create", key="vcp_create_init"):
            if not name.strip():
                st.error("Name required.")
            else:
                new_id = "INIT_" + uuid4().hex[:16].upper()
                _execute(
                    session,
                    "INSERT INTO AI_INITIATIVE (INITIATIVE_ID,INITIATIVE_NAME,DESCRIPTION,"
                    "OWNER_NAME,LIFECYCLE_STAGE,BUSINESS_OUTCOME) "
                    "VALUES (?, ?, ?, ?, ?, ?)",
                    [
                        new_id,
                        name.strip(),
                        desc.strip() or None,
                        owner.strip() or None,
                        stage,
                        outcome.strip() or None,
                    ],
                )
                _execute(
                    session,
                    "UPDATE ASSESSMENT_RUNS SET INITIATIVE_ID = ? WHERE RUN_ID = ?",
                    [new_id, run_id],
                )
                st.session_state["vcp_msg"] = f"Created and linked: {name.strip()}"
                _rerun()


def _render_evidence_upload(session, run_id):
    st.subheader("Upload evidence")
    revision_id = None
    revision_no = None
    revision_status = None
    try:
        revision_df = _query(
            session,
            "SELECT revision.REVISION_ID, revision.REVISION_NO, revision.STATUS, "
            "IFF(case_record.ACTIVE_DRAFT_REVISION_ID = revision.REVISION_ID, TRUE, FALSE) "
            "AS IS_ACTIVE_DRAFT "
            "FROM ASSESSMENT_REVISION revision "
            "JOIN ASSESSMENT_CASE case_record ON case_record.CASE_ID = revision.CASE_ID "
            "WHERE revision.RUN_ID = ?",
            [run_id],
        )
        if not revision_df.empty:
            revision_id = _text(revision_df.iloc[0]["REVISION_ID"], "")
            revision_no = _integer(revision_df.iloc[0]["REVISION_NO"])
            revision_status = _text(revision_df.iloc[0]["STATUS"], "")
            is_active_draft = bool(revision_df.iloc[0]["IS_ACTIVE_DRAFT"])
            if is_active_draft and revision_status in {"DRAFT", "FAILED"}:
                st.caption(
                    f"Revision {revision_no} · Draft · New files remain pending until reassessment and publication."
                )
            else:
                st.info(
                    f"Revision {revision_no} is {revision_status}. "
                    "Select its active Draft Revision to add evidence."
                )
    except Exception:
        is_active_draft = True

    upload_enabled = revision_id is None or (
        is_active_draft and revision_status in {"DRAFT", "FAILED"}
    )
    files = None
    if upload_enabled:
        files = st.file_uploader(
            "Upload .txt or .pdf files",
            type=["txt", "pdf"],
            accept_multiple_files=True,
            key="vcp_txt_up",
        )

    if files:
        for uf in files:
            raw = uf.read()
            uf.seek(0)
            extension = uf.name.rsplit(".", 1)[-1].lower() if "." in uf.name else ""

            if not raw:
                st.error(f"**{uf.name}**: Empty.")
                continue
            if len(raw) > 20_000_000:
                st.error(f"**{uf.name}**: Exceeds 20 MB.")
                continue

            sha = hashlib.sha256(raw).hexdigest()
            try:
                dup = _query(
                    session,
                    "SELECT COUNT(*) AS C FROM EVIDENCE_ITEMS "
                    "WHERE RUN_ID = ? AND CONTENT_SHA256 = ?",
                    [run_id, sha],
                )
                if not dup.empty and _integer(dup.iloc[0]["C"]) > 0:
                    st.warning(f"**{uf.name}**: Duplicate SHA-256.")
                    continue
            except Exception:
                pass

            ev_id = (
                f"EV_{extension.upper()}_"
                f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{sha[:8]}"
            )
            relative_path = f"{run_id}/{ev_id}/{sha}.{extension}"
            stage_path = f"@READINESSOPS_EVIDENCE_STAGE/{relative_path}"

            try:
                session.file.put_stream(
                    io.BytesIO(raw),
                    stage_path,
                    auto_compress=False,
                    overwrite=False,
                )
            except Exception:
                st.error(f"**{uf.name}**: Original file storage failed.")
                continue

            if extension == "txt":
                try:
                    content = raw.decode("utf-8", errors="strict")
                except UnicodeDecodeError:
                    st.error(f"**{uf.name}**: Invalid UTF-8.")
                    continue
                if not content.strip():
                    st.error(f"**{uf.name}**: Empty text.")
                    continue
                if len(content) > 50_000:
                    st.error(
                        f"**{uf.name}**: Exceeds 50,000 chars "
                        f"({len(content):,})."
                    )
                    continue
                source_type = "UPLOADED_TXT"
                media_type = "text/plain"
                parser_name = "UTF8_TEXT"
                page_count = None

            elif extension == "pdf":
                try:
                    parsed_df = _query(
                        session,
                        "SELECT "
                        "PARSED:value:content::VARCHAR AS CONTENT, "
                        "PARSED:error::VARCHAR AS ERROR, "
                        "PARSED:metadata:pageCount::NUMBER AS PAGE_COUNT "
                        "FROM (SELECT AI_PARSE_DOCUMENT("
                        "TO_FILE('@READINESSOPS_EVIDENCE_STAGE', ?), "
                        "{'mode': 'LAYOUT'}, TRUE) AS PARSED)",
                        [relative_path],
                    )
                    if parsed_df.empty:
                        st.error(f"**{uf.name}**: PDF parsing returned no result.")
                        continue
                    parse_error = _text(parsed_df.iloc[0]["ERROR"], "")
                    content = _text(parsed_df.iloc[0]["CONTENT"], "")
                    page_count = _integer(parsed_df.iloc[0]["PAGE_COUNT"])
                    if parse_error:
                        st.error(f"**{uf.name}**: PDF parsing failed.")
                        continue
                    if not content.strip():
                        st.error(f"**{uf.name}**: No text extracted from PDF.")
                        continue
                except Exception:
                    st.error(f"**{uf.name}**: PDF parsing failed.")
                    continue

                source_type = "UPLOADED_PDF"
                media_type = "application/pdf"
                parser_name = "AI_PARSE_DOCUMENT_LAYOUT"

            else:
                st.error(f"**{uf.name}**: Unsupported file type.")
                continue

            _execute(
                session,
                "INSERT INTO EVIDENCE_ITEMS ("
                "EVIDENCE_ID,RUN_ID,QUESTION_ID,"
                "EVIDENCE_TITLE,EVIDENCE_TEXT,EVIDENCE_STATUS,"
                "SOURCE_FILENAME,SOURCE_TYPE,MEDIA_TYPE,"
                "CONTENT_SHA256,BYTE_COUNT,CHAR_COUNT,STAGE_PATH,"
                "PARSER_NAME,PAGE_COUNT,UPLOADED_AT,UPLOADED_BY"
                ") VALUES ("
                "?, ?, NULL, ?, ?, 'VALIDATED', ?, ?, ?, "
                "?, ?, ?, ?, ?, TRY_TO_NUMBER(?), CURRENT_TIMESTAMP(), CURRENT_USER())",
                [
                    ev_id, run_id, uf.name, content, uf.name,
                    source_type, media_type, sha, len(raw), len(content),
                    stage_path, parser_name, page_count,
                ],
            )
            if revision_id:
                registration = _call_json(
                    session,
                    "CALL SP_REGISTER_REVISION_EVIDENCE(?, ?, NULL)",
                    [revision_id, ev_id],
                )
                if registration.get("status") != "OK":
                    _execute(
                        session,
                        "DELETE FROM EVIDENCE_ITEMS WHERE EVIDENCE_ID = ? AND RUN_ID = ?",
                        [ev_id, run_id],
                    )
                    st.error(
                        f"**{uf.name}**: Revision registration failed: "
                        f"{registration.get('error', 'Unknown error')}"
                    )
                    continue
            st.success(
                f"**{uf.name}** stored, parsed, and validated "
                f"({len(content):,} chars)"
            )

    try:
        ev_df = _query(
            session,
            "SELECT evidence.EVIDENCE_ID,evidence.SOURCE_FILENAME,evidence.SOURCE_TYPE,"
            "evidence.CHAR_COUNT,evidence.PAGE_COUNT,evidence.PARSER_NAME,"
            "evidence.STAGE_PATH,evidence.EVIDENCE_STATUS,evidence.UPLOADED_AT,"
            "COALESCE(lineage.SNAPSHOT_ROLE, 'LEGACY') AS REVISION_ROLE "
            "FROM EVIDENCE_ITEMS evidence "
            "LEFT JOIN ASSESSMENT_REVISION revision ON revision.RUN_ID = evidence.RUN_ID "
            "LEFT JOIN ASSESSMENT_REVISION_EVIDENCE lineage "
            "ON lineage.REVISION_ID = revision.REVISION_ID "
            "AND lineage.EVIDENCE_ID = evidence.EVIDENCE_ID "
            "WHERE evidence.RUN_ID = ? "
            "AND SOURCE_TYPE IN ('UPLOADED_TXT', 'UPLOADED_PDF') "
            "ORDER BY evidence.UPLOADED_AT DESC",
            [run_id],
        )
        if not ev_df.empty:
            st.caption(f"{len(ev_df)} uploaded file(s)")
            _show_df(ev_df.rename(columns={
                "EVIDENCE_ID": "ID",
                "SOURCE_FILENAME": "File",
                "SOURCE_TYPE": "Type",
                "CHAR_COUNT": "Chars",
                "PAGE_COUNT": "Pages",
                "PARSER_NAME": "Parser",
                "STAGE_PATH": "Stored path",
                "EVIDENCE_STATUS": "Status",
                "UPLOADED_AT": "Uploaded",
                "REVISION_ROLE": "Revision role",
            }))
    except Exception:
        pass

def _render_generate_dp(session, run_id):
    st.subheader("Generate Decision Pack")
    st.info("Produces 4 AI Draft sections requiring human review before publication.")
    instr = st.text_area("Additional instruction", height=70, key="vcp_dp_instr",
                         placeholder="Optional focus areas or constraints.")
    if "vcp_dp_running" not in st.session_state:
        st.session_state.vcp_dp_running = False
    if st.button("Generate", type="primary", disabled=st.session_state.vcp_dp_running, key="vcp_gen_dp"):
        st.session_state.vcp_dp_running = True
        with st.spinner("Generating Decision Pack..."):
            res = _call_json(
                session,
                "CALL SP_GENERATE_DECISION_PACK(?, ?)",
                [run_id, instr.strip() or None],
            )
            if res.get("status") == "COMPLETED":
                st.session_state["vcp_msg"] = f"Decision Pack: {res.get('sections',0)} sections generated."
            elif res.get("status") == "SKIPPED":
                st.session_state["vcp_msg"] = "Skipped: evidence unchanged."
            else:
                st.session_state["vcp_err"] = f"Failed: {res.get('error','Unknown')}"
        st.session_state.vcp_dp_running = False
        _rerun()


def _render_agent_execution_trace(session, run_id):
    st.subheader("Agent execution trace")
    st.caption(
        "Governed Snowflake steps recorded for the latest Decision Pack run. "
        "The trace adds observability without adding Cortex inference calls."
    )

    try:
        run_df = _query(
            session,
            "SELECT AGENT_RUN_ID,STATUS,MODEL_NAME,PROMPT_VERSION,STARTED_AT,"
            "COMPLETED_AT,ERROR_MESSAGE FROM GOVERNANCE_AGENT_RUN "
            "WHERE ASSESSMENT_RUN_ID = ? AND WORKFLOW_TYPE = 'DECISION_PACK' "
            "ORDER BY CREATED_AT DESC LIMIT 1",
            [run_id],
        )
    except Exception as exc:
        st.warning(f"Execution trace is not available: {exc}")
        return

    if run_df.empty:
        st.info("Generate a Decision Pack to record its governed execution trace.")
        return

    run = run_df.iloc[0]
    agent_run_id = _text(run["AGENT_RUN_ID"])
    run_status = _text(run["STATUS"])
    status_tone = {
        "COMPLETED": "success", "RUNNING": "info", "FAILED": "danger"
    }.get(run_status, "neutral")

    st.markdown(
        f"{_badge(run_status, status_tone)} "
        f"<b>{_escaped(agent_run_id)}</b>",
        unsafe_allow_html=True,
    )
    st.caption(
        f"Model: {_text(run.get('MODEL_NAME'))} · "
        f"Prompt: {_text(run.get('PROMPT_VERSION'))} · "
        f"Started: {_timestamp(run.get('STARTED_AT'))} · "
        f"Completed: {_timestamp(run.get('COMPLETED_AT'))}"
    )

    try:
        steps = _query(
            session,
            "SELECT STEP_SEQUENCE,STEP_CODE,STEP_NAME,STATUS,STARTED_AT,"
            "COMPLETED_AT,DURATION_MS,STEP_DETAIL,ERROR_MESSAGE "
            "FROM GOVERNANCE_AGENT_RUN_STEP WHERE AGENT_RUN_ID = ? "
            "ORDER BY STEP_SEQUENCE",
            [agent_run_id],
        )
    except Exception as exc:
        st.warning(f"Run-step records could not be loaded: {exc}")
        return

    if steps.empty:
        st.info("This earlier run predates governed run-step recording.")
        return

    completed_count = _integer((steps["STATUS"].astype(str) == "COMPLETED").sum())
    total_duration_ms = sum(
        _integer(value) for value in steps["DURATION_MS"].tolist()
    )
    m1, m2, m3 = st.columns(3)
    m1.metric("Recorded steps", len(steps))
    m2.metric("Completed", completed_count)
    m3.metric("Recorded duration", f"{total_duration_ms / 1000:.1f}s")

    with st.expander("Inspect governed run steps", expanded=True):
        for _, step in steps.iterrows():
            step_status = _text(step["STATUS"])
            step_tone = {
                "COMPLETED": "success", "RUNNING": "info", "FAILED": "danger"
            }.get(step_status, "neutral")
            duration_ms = _integer(step.get("DURATION_MS"))
            st.markdown(
                f"{_badge(step_status, step_tone)} "
                f"**{_integer(step['STEP_SEQUENCE'])}. {_escaped(step['STEP_NAME'])}** "
                f"`{_escaped(step['STEP_CODE'])}`",
                unsafe_allow_html=True,
            )
            timing = (
                f"Started: {_timestamp(step.get('STARTED_AT'))} · "
                f"Completed: {_timestamp(step.get('COMPLETED_AT'))}"
            )
            if duration_ms:
                timing += f" · {duration_ms / 1000:.1f}s"
            st.caption(timing)
            if _text(step.get("ERROR_MESSAGE"), ""):
                st.error(_text(step.get("ERROR_MESSAGE")))

    if run_status == "FAILED" and _text(run.get("ERROR_MESSAGE"), ""):
        st.error(f"Run failed: {_text(run.get('ERROR_MESSAGE'))}")


def _render_decision_pack_review(session, run_id):
    st.subheader("Decision Pack sections")
    try:
        run_df = _query(
            session,
            "SELECT AGENT_RUN_ID,STATUS,COMPLETED_AT FROM GOVERNANCE_AGENT_RUN "
            "WHERE ASSESSMENT_RUN_ID = ? AND WORKFLOW_TYPE = 'DECISION_PACK' "
            "AND STATUS = 'COMPLETED' ORDER BY CREATED_AT DESC LIMIT 1",
            [run_id],
        )
    except Exception:
        run_df = pd.DataFrame()

    if run_df.empty:
        st.info("No Decision Pack generated yet.")
        return

    dp_run_id = _text(run_df.iloc[0]["AGENT_RUN_ID"])
    st.caption(f"Run: {dp_run_id} · Completed: {_timestamp(run_df.iloc[0]['COMPLETED_AT'])}")

    try:
        props = _query(
            session,
            "SELECT PROPOSAL_ID,PROPOSAL_TYPE,TITLE,DESCRIPTION,SEVERITY,"
            "PRIORITY,RATIONALE,STATUS,REVIEW_COMMENT,REVIEWED_BY,REVIEWED_AT,"
            "PROPOSAL_PAYLOAD FROM GOVERNANCE_AGENT_PROPOSAL "
            "WHERE AGENT_RUN_ID = ? "
            "ORDER BY CASE PROPOSAL_TYPE "
            "WHEN 'DECISION_GOVERNANCE' THEN 1 WHEN 'DECISION_VALUE' THEN 2 "
            "WHEN 'DECISION_MODEL_ROUTING' THEN 3 WHEN 'DECISION_PORTFOLIO' THEN 4 ELSE 5 END",
            [dp_run_id],
        )
    except Exception as exc:
        st.error(f"Load failed: {exc}")
        return

    if props.empty:
        st.info("No proposals found for this run.")
        return

    labels = {"DECISION_GOVERNANCE": "Governance", "DECISION_VALUE": "Value",
              "DECISION_MODEL_ROUTING": "Routing", "DECISION_PORTFOLIO": "Portfolio"}
    tabs = st.tabs([labels.get(_text(r["PROPOSAL_TYPE"]), "?") for _, r in props.iterrows()])

    for tab, (_, row) in zip(tabs, props.iterrows()):
        with tab:
            pid = _text(row["PROPOSAL_ID"])
            status = _text(row["STATUS"])
            st.markdown(_origin_badge(status), unsafe_allow_html=True)
            st.markdown(
                f"<div style='border:1px solid var(--line,#dfe5ee);border-radius:12px;"
                f"padding:.9rem 1rem;margin:.5rem 0;'>"
                f"<b>{_escaped(row['TITLE'])}</b><br>"
                f"<span style='color:var(--muted,#667085)'>{_escaped(row['DESCRIPTION'])}</span>"
                f"</div>", unsafe_allow_html=True)
            detail = []
            if _text(row.get("PRIORITY"), ""):
                detail.append(f"Priority: {_text(row.get('PRIORITY'))}")
            if _text(row.get("RATIONALE"), ""):
                detail.append(f"Rationale: {_text(row.get('RATIONALE'))}")
            if detail:
                st.caption(" · ".join(detail))

            payload = row.get("PROPOSAL_PAYLOAD")
            if payload and str(payload).strip() not in ("", "None", "nan"):
                with st.expander("Structured detail"):
                    try:
                        p = json.loads(str(payload)) if isinstance(payload, str) else payload
                        if isinstance(p, dict):
                            for k, v in p.items():
                                if k == "source_evidence_ids":
                                    st.caption(f"Grounded in: {', '.join(v) if isinstance(v, list) else v}")
                                elif isinstance(v, list):
                                    st.markdown(f"**{k.replace('_',' ').title()}**")
                                    for i in v:
                                        st.write(f"- {i}")
                                else:
                                    st.write(f"**{k.replace('_',' ').title()}:** {v}")
                    except (json.JSONDecodeError, TypeError):
                        st.code(str(payload)[:1500])

            if status == "REVIEW_REQUIRED":
                with st.expander("Edit before deciding"):
                    et = st.text_input("Title", _text(row["TITLE"], ""), key=f"vcp_et_{pid}")
                    ed = st.text_area("Description", _text(row["DESCRIPTION"], ""), key=f"vcp_ed_{pid}", height=100)
                    er = st.text_input("Reason", key=f"vcp_er_{pid}")
                    if st.button("Save", key=f"vcp_esv_{pid}"):
                        r = _call_json(
                            session,
                            "CALL SP_EDIT_AGENT_PROPOSAL(?, ?, ?, ?)",
                            [pid, et, ed, er.strip() or None],
                        )
                        if r.get("status") == "OK":
                            st.session_state["vcp_msg"] = "Edit saved."
                        else:
                            st.session_state["vcp_err"] = r.get("error", "Failed")
                        _rerun()

                cmt = st.text_input("Comment", key=f"vcp_cmt_{pid}", placeholder="Optional")
                c1, c2, _ = st.columns([1, 1, 4])
                with c1:
                    if st.button("Approve", key=f"vcp_ap_{pid}", type="primary"):
                        r = _call_json(
                            session,
                            "CALL SP_REVIEW_AGENT_PROPOSAL(?, ?, ?)",
                            [pid, "APPROVE", cmt.strip() or None],
                        )
                        st.session_state["vcp_msg" if r.get("status")=="OK" else "vcp_err"] = (
                            f"Approved: {_text(row['TITLE'])}" if r.get("status")=="OK" else r.get("error",""))
                        _rerun()
                with c2:
                    if st.button("Reject", key=f"vcp_rj_{pid}"):
                        r = _call_json(
                            session,
                            "CALL SP_REVIEW_AGENT_PROPOSAL(?, ?, ?)",
                            [pid, "REJECT", cmt.strip() or None],
                        )
                        st.session_state["vcp_msg" if r.get("status")=="OK" else "vcp_err"] = (
                            f"Rejected: {_text(row['TITLE'])}" if r.get("status")=="OK" else r.get("error",""))
                        _rerun()
            elif _text(row["REVIEWED_BY"]):
                st.caption(f"Decided by {_text(row['REVIEWED_BY'])} · {_timestamp(row['REVIEWED_AT'])}")

    # Publish approved
    approved = props[props["STATUS"].astype(str) == "APPROVED"]
    if not approved.empty:
        st.divider()
        st.write(f"{len(approved)} section(s) approved, awaiting publication.")
        confirm = st.checkbox("Confirm publication of approved sections.", key="vcp_pub_confirm")
        if st.button("Publish", type="primary", disabled=not confirm, key="vcp_pub_btn"):
            r = _call_json(session, "CALL SP_PUBLISH_AGENT_RUN(?)", [dp_run_id])
            if r.get("status") == "OK":
                st.session_state["vcp_msg"] = f"Published {r.get('published_decisions',0)} decision(s)."
            else:
                st.session_state["vcp_err"] = r.get("error", "Failed")
            _rerun()


def _render_published_decisions(session, run_id):
    st.subheader("Published Governed Decision Records")
    try:
        dr_df = _query(
            session,
            "SELECT DECISION_RECORD_ID,DECISION_TYPE,TITLE,DESCRIPTION,"
            "PUBLISHED_BY,PUBLISHED_AT FROM GOVERNED_DECISION_RECORD "
            "WHERE ASSESSMENT_RUN_ID = ? ORDER BY PUBLISHED_AT DESC",
            [run_id],
        )
    except Exception:
        dr_df = pd.DataFrame()

    if dr_df.empty:
        st.info("No governed decision records published for this run.")
        return

    labels = {"DECISION_GOVERNANCE": "Governance", "DECISION_VALUE": "Value",
              "DECISION_MODEL_ROUTING": "Routing", "DECISION_PORTFOLIO": "Portfolio"}
    for _, row in dr_df.iterrows():
        dt = _text(row["DECISION_TYPE"])
        st.markdown(
            f"<div style='border:1px solid var(--line,#dfe5ee);border-radius:12px;"
            f"padding:.85rem 1rem;margin:.4rem 0;'>"
            f"{_badge(labels.get(dt, dt), 'info')} "
            f"{_badge('Published Governed Record', 'success')}"
            f"<br><b>{_escaped(row['TITLE'])}</b><br>"
            f"<span style='color:var(--muted,#667085)'>{_escaped(row['DESCRIPTION'])}</span><br>"
            f"<small>Published by {_escaped(row['PUBLISHED_BY'])} · "
            f"{_escaped(_timestamp(row['PUBLISHED_AT']))}</small>"
            f"</div>", unsafe_allow_html=True)


def _render_portfolio(session):
    st.subheader("AI Portfolio")
    try:
        pf = _query(session,
            "SELECT INITIATIVE_NAME,LIFECYCLE_STAGE,OWNER_NAME,"
            "GOVERNANCE_READINESS,VALUE_CONFIDENCE,ROUTING_APPROACH,"
            "PORTFOLIO_RECOMMENDATION,PORTFOLIO_PRIORITY,LAST_DECISION_AT "
            "FROM V_AI_PORTFOLIO ORDER BY PORTFOLIO_PRIORITY DESC NULLS LAST")
    except Exception as exc:
        st.warning(f"Portfolio view not available: {exc}")
        return

    if pf.empty:
        st.info("No initiatives with published Decision Pack records.")
        return

    m1, m2, m3 = st.columns(3)
    m1.metric("Initiatives", len(pf))
    m2.metric("PROCEED", _integer((pf.get("PORTFOLIO_RECOMMENDATION", pd.Series(dtype=str)).astype(str) == "PROCEED").sum()))
    m3.metric("HOLD", _integer((pf.get("PORTFOLIO_RECOMMENDATION", pd.Series(dtype=str)).astype(str) == "HOLD").sum()))

    _show_df(pf[["INITIATIVE_NAME","LIFECYCLE_STAGE","OWNER_NAME",
                  "GOVERNANCE_READINESS","VALUE_CONFIDENCE",
                  "PORTFOLIO_RECOMMENDATION","PORTFOLIO_PRIORITY"]].rename(columns={
        "INITIATIVE_NAME": "Initiative", "LIFECYCLE_STAGE": "Stage",
        "OWNER_NAME": "Owner", "GOVERNANCE_READINESS": "Governance",
        "VALUE_CONFIDENCE": "Value", "PORTFOLIO_RECOMMENDATION": "Recommendation",
        "PORTFOLIO_PRIORITY": "Priority"}))


# -- Public entry point -------------------------------------------------------

def render_value_control_plane(session, assessment_run_id: str, actor: str) -> None:
    """Render the Foundation Slice 1 workspace.

    Call from streamlit_app.py when the user selects the Value Control Plane
    workspace. Requires an active Snowpark session and the selected run ID.
    """
    # Retrieve selected run row
    try:
        run_row = _query(
            session,
            "SELECT RUN_ID, RUN_NAME, ORGANIZATION_NAME, "
            "COALESCE(INITIATIVE_ID,'') AS INITIATIVE_ID "
            "FROM ASSESSMENT_RUNS WHERE RUN_ID = ?",
            [assessment_run_id],
        ).iloc[0]
    except Exception as exc:
        st.error(f"Could not load assessment run: {exc}")
        return

    # Flash messages
    msg = st.session_state.pop("vcp_msg", None)
    if msg:
        st.success(msg)
    err = st.session_state.pop("vcp_err", None)
    if err:
        st.error(err)

    st.header("Value Control Plane")
    st.caption(f"Assessment: {_text(run_row['RUN_NAME'])} · Actor: {actor}")

    vcp_tab = st.radio(
        "Section",
        ["Initiative", "Evidence", "Decision Pack", "Published", "Portfolio"],
        horizontal=True, key="vcp_section_nav")

    if vcp_tab == "Initiative":
        _render_initiative(session, assessment_run_id, run_row)
    elif vcp_tab == "Evidence":
        _render_evidence_upload(session, assessment_run_id)
    elif vcp_tab == "Decision Pack":
        if _text(run_row.get("INITIATIVE_ID"), ""):
            _render_generate_dp(session, assessment_run_id)
            _render_agent_execution_trace(session, assessment_run_id)
            st.divider()
        else:
            st.warning("Link an AI Initiative before generating a Decision Pack.")
        _render_decision_pack_review(session, assessment_run_id)
    elif vcp_tab == "Published":
        _render_published_decisions(session, assessment_run_id)
    elif vcp_tab == "Portfolio":
        _render_portfolio(session)

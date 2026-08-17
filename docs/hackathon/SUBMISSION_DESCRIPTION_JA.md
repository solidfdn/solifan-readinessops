# 提出説明文

## 一文説明

ReadinessOpsは、TXT／PDF EvidenceからGovernance・Value・Model Routing・Portfolioの4 Section Decision Packを生成し、人のレビューと明示的なPublishを経て、正式な判断記録・Portfolio・Auditへ変換するSnowflake-nativeのAI Value Control Planeです。

## 解決する課題

企業のAI Initiativeでは、AIの提案内容だけでなく、次を継続管理する必要があります。

- 何のEvidenceに基づくか
- Governanceと事業価値をどう評価したか
- どのModel Routingが適切か
- 誰が承認したか
- 何が正式記録になったか
- Portfolio内で優先すべきか

ReadinessOpsは、この判断過程をSnowflake内で一つの運用フローにします。

## 制御境界

```text
Evidence Supplied
→ AI Drafted
→ Human Reviewed
→ Explicitly Published
→ Governed Record
```

AIはEvidenceを解析して提案できますが、自ら承認・公開することはできません。

## 技術的実装

- Snowflake StreamlitによるValue Control Plane
- AI InitiativeとAssessment Runの紐付け
- TXT／PDF Evidence Upload
- Original FileのSnowflake Stage保持
- Cortex `AI_PARSE_DOCUMENT`によるPDF解析
- Cortex `COMPLETE`による4 Section Decision Pack生成
- 完全な4 Section、Required Field、Priority、Evidence IDの厳格検証
- Proposal DraftとGoverned Decision Recordの分離
- Human Edit／Approve／Reject
- 明示的Publish確認
- 重複正式記録・重複Audit Historyの防止
- Governance／Value／Routing／PortfolioのPublished Record
- `V_AI_PORTFOLIO`によるInitiative比較
- Actor、Timestamp、State Transitionを保持するAudit History

## 実社会との関連性

対象利用者はCCoE、AI Governance、Risk Management、事業責任者、内部監査、経営層です。

ReadinessOpsは一度の診断レポートではなく、Evidence、価値、モデル選択、人の責任、正式記録、Portfolio判断を継続運用するControl Planeです。正式記録はBI、Reporting、次のGoverned Workflowへ接続できます。

## 実機確認

専用の`RUN_FINALIST_E2E_001`で以下を確認しました。

- AI Initiative作成・紐付け
- TXT Evidenceの検証・原本保持
- PDF Evidenceの原本保持・Cortex解析
- 4 Section Decision Pack生成
- 5段階のGoverned Run Steps（5件記録、5件完了、失敗0件）
- 4件のHuman Approval
- 明示的Publishによる4件のGoverned Decision Record
- 8件のAPPROVE／PUBLISH Audit Event
- Published Workspace
- Portfolio Workspace
- Audit Trail
- `RUN_001`へのProposal漏洩0件
- Production Streamlit Deployment成功

## 既存機能との互換性

既存のGap、Risk、Actionフローは維持しています。`DECISION_*` Proposalだけを新しい`GOVERNED_DECISION_RECORD`へ公開し、Gap、Risk、Actionは従来のCanonical Mappingを使用します。

## 現在の制約

- 合成データによる最終選考用実装です。
- 生成Modelは現行Procedure内で固定しています。
- Legacy Riskは専用Risk Tableではなく`READINESS_GAPS`へ`[RISK]`付きで正規化します。
- 本番利用にはRBAC、Tenant分離、Retention、Monitoring、変更管理が必要です。
- 現在はStreamlit in SnowflakeとしてDeploy済みで、Snowflake Native App Package化は次の製品化段階です。

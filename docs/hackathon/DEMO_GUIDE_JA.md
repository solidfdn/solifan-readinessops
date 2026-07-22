# 4分デモ手順

## 0:00–0:30　課題と制御境界

画面上部の4ステップを示します。

> Evidence不足を起点に、AIがGap・Risk・Actionを提案します。
> AI出力は直接正式データになりません。
> 人が承認し、明示的にPublishしたものだけが統制済み記録になります。

件数はデモ操作によって変わるため、固定値ではなく意味を説明します。

## 0:30–1:10　自然言語によるレビュー優先度

`Review setup`を開きます。

`Additional business instruction`へ入力します。

```text
Prioritize governance issues that could block executive approval within the next 90 days. Do not propose any gap, risk, or action that is not supported by the supplied assessment evidence.
```

`Generate AI draft proposals`を実行します。

示す内容:

- Question、Answer、Evidence、Rule Contextを入力に使用
- 追加指示は優先度を補足する
- Evidence groundingの固定ルールは解除されない
- 生成結果は`REVIEW_REQUIRED`で保存される
- AIは承認もPublishもできない

## 1:10–2:15　根拠を確認して人が判断

`Review queue` → `Review by issue`を開きます。

最初のAssessment issueが既に表示されている場合は、そのまま使用します。必要な場合だけプルダウンで変更します。

示す内容:

- Current Answer
- Evidence
- Requirement / Rule Context
- 関連するGap / Risk / Action
- Why the AI raised this proposal
- Source traceability

Actionを1件開き、Decision commentへ入力します。

```text
DEMO_APPROVE — reviewed against the supplied evidence and current governance requirement.
```

`Approve`を実行します。

件数変化:

- Needs human decision: 1減る
- Approved, not published: 1増える
- Published governance records: 変化しない

## 2:15–3:00　統制されたPublish

`Approved & publish`を開きます。

確認チェックを入れ、`Publish approved proposals`を実行します。

示す点:

- 承認だけでは正式記録にならない
- Publishを明示実行して初めて正式記録になる
- Source Proposal IDにより二重公開を防止する

承認済み提案がない場合は、`Back to review queue`で戻れます。

## 3:00–3:35　正式記録とトレーサビリティ

`Published records`を開きます。

新しく公開した記録を選び、以下を示します。

- Record type
- Description
- Owner / Target
- Assessment Question
- Source Proposal
- Agent Run

## 3:35–4:00　監査履歴

`Audit trail`を開きます。

最新の2件を示します。

1. `PUBLISH`
2. `APPROVE`

締め:

> AIが提案し、人が承認し、正式記録と判断履歴を残す。
> ReadinessOpsは診断画面ではなく、Enterprise AI Governanceを継続運用する基盤です。

# 4分デモ手順

## 0:00–0:30　課題と制御境界

上部の4ステップを示します。

> Evidence不足を起点に、AIがGap・Risk・Actionを提案します。
> ただし、AI出力は直接正式データになりません。
> 人が承認し、明示的にPublishしたものだけが統制済み記録になります。

## 0:30–1:15　新しいAI Reviewを生成

`Review setup`を開きます。

Additional business instruction:

```text
Prioritize governance issues that could block executive approval within the next 90 days. Do not propose any gap, risk, or action that is not supported by the supplied assessment evidence.
```

`Generate AI draft proposals`を実行します。

説明:

- Question、Answer、Evidence、Rule Contextを入力に使用
- CortexモデルがGap、Risk、ActionのDraftを生成
- 生成結果は`REVIEW_REQUIRED`で保存される

## 1:15–2:15　根拠を確認して人が判断

`Review queue` → `Review by issue`を開きます。

1つのAssessment issueを選択し、以下を示します。

- Current Answer
- Evidence
- Requirement / Rule Context
- 関連するGap / Risk / Action
- Why the AI raised this proposal

Decision comment:

```text
DEMO_APPROVE
```

Actionを1件Approveします。

上部件数が次のように変化することを示します。

- Needs human decision: -1
- Approved, not published: +1
- Published governance records: 変化なし

## 2:15–3:00　統制されたPublish

`Approved & publish`を開きます。

確認チェックを入れ、`Publish approved proposals`を実行します。

示す点:

- 承認しただけでは正式記録にならない
- Publishを明示実行して初めて正式Actionになる
- 二重Publishを防ぐSource Proposal IDを保持する

## 3:00–3:35　正式記録とトレーサビリティ

`Published records`を開きます。

- 公開済みActionを一覧から選択
- Assessment question
- Publication source
- Agent run
- Source proposal

を示します。

## 3:35–4:00　監査履歴

`Audit trail`を開きます。

最新の2件を示します。

1. `PUBLISH / ACTION`
2. `APPROVE / ACTION`

締め:

> AIが提案し、人が承認し、正式記録と監査履歴を残す。
> ReadinessOpsは診断画面ではなく、Enterprise AI Governanceを継続運用する基盤です。

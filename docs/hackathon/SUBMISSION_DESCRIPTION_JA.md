# 提出説明文

## 一文説明

ReadinessOpsは、AI導入準備のEvidence不足を起点に、AIがGap・Risk・Actionを提案し、人の承認と明示的なPublishを経て、正式なガバナンス記録と判断履歴へ変換するSnowflake-nativeの運用基盤です。

## 解決する課題

AIガバナンスは、成熟度スコアやレポートを出すだけでは運用できません。

```text
Question
→ Answer
→ Evidence
→ Gap
→ Risk
→ Action
→ Human Decision
→ Published Record
```

この判断過程と根拠を継続管理する必要があります。

## 制御境界

```text
Requirement / Rule Context
→ AI Proposed
→ Human Approved
→ Explicitly Published
```

AIは提案できますが、自ら承認・公開することはできません。

## 技術的実装

- Snowflake StreamlitによるHuman Review Workspace
- Snowflake CortexによるGap・Risk・Actionの構造化提案
- SQL Stored Procedureによる生成、承認・却下、Publish
- DraftとGoverned Recordの分離
- Source Proposal IDによる二重公開防止
- Question、Answer、Evidence、Rule Context、Agent RunまでのTraceability
- 承認・却下・公開を記録するAudit History
- Issue単位のReview UI
- Published recordsとAudit trailの一覧＋詳細表示
- 1始まりの通番と空状態からのBack操作

## 実社会との関連性

企業がAIを導入する際に必要なのは、一度の診断ではありません。

- Evidence不足
- 判断責任者
- 優先度
- 期限
- 承認理由
- 正式記録
- 監査履歴

を継続して管理する必要があります。

ReadinessOpsは、CCoE、リスク管理、データガバナンス、内部監査、経営層が同じ判断履歴を共有するOperating Platformを目指します。

## 実機確認

- 5 Gap、2 Risk、5 ActionのDraft生成
- Gapの承認・Publish
- RiskのReject・非公開
- Actionの承認・Publish
- 承認とPublishの履歴分離
- 重複Publish防止
- Published Recordから根拠への追跡
- 本番App表示
- Git main反映

## 現在の制約

専用Riskテーブルは未実装です。承認されたRiskは`READINESS_GAPS`へ`[RISK]`付きで正規化し、Source ProposalによってRiskとして追跡します。

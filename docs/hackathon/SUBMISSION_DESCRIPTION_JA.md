# 提出説明文

## 一文説明

ReadinessOpsは、AI導入準備のEvidence不足を起点に、
AIがGap・Risk・Actionを提案し、人の承認と明示的なPublishを経て、
正式なガバナンス記録と監査履歴へ変換するSnowflake Nativeの運用基盤です。

## 解決する課題

AIガバナンス診断は、スコアやレポートを出して終わりがちです。
一方、実務では次の処理を継続して管理する必要があります。

Question → Evidence → Gap → Risk → Action → Approval

ReadinessOpsは、この判断過程と根拠をSnowflake上の構造化データとして保持します。

## 技術的実装

- Snowflake StreamlitによるHuman Review Workspace
- Snowflake Cortexを利用したGap・Risk・Actionの提案生成
- SQL Stored Procedureによる生成、承認・却下、Publishの状態遷移
- DraftとCanonical Recordの分離
- Source Proposal IDによる重複公開防止
- Question、Answer、Evidence、Rule Context、Agent RunまでのTraceability
- 承認・却下・公開を記録するAudit History

## 実社会との関連性

企業がAIを導入する際に必要なのは、一度の成熟度診断だけではありません。
Evidenceの不足、責任者、期限、承認、正式記録を継続管理する必要があります。

ReadinessOpsは、CCoE、リスク管理、データガバナンス、
内部監査などが同じ判断履歴を共有できるOperating Platformを目指します。

## 完成度

実機で次の一連動作を確認済みです。

1. AI Proposal生成
2. Human Approval
3. Controlled Publication
4. Canonical Actionへの登録
5. Approval / Publish履歴の記録
6. Published Recordから根拠への追跡

# 最終選考 4分デモ手順

## 0:00–0:25　制御境界

`Finalist E2E Validation`を選択し、`Value Control Plane`を開きます。

> ReadinessOpsは、EvidenceをAIの提案、Human Review、正式なPublishへつなげます。AIは提案できますが、自ら承認・公開はできません。

## 0:25–0:50　AI Initiative

`Initiative`を開き、`Claims Triage AI — E2E`がAssessment Runへ紐づいていることを示します。

示す内容:

- Initiative名
- Owner
- Stage
- 選択中のAssessment Run

## 0:50–1:25　TXT／PDF Evidence

`Evidence`を開き、合成TXTと合成PDFをアップロードします。

示す内容:

- `stored, parsed, and validated`の成功表示
- TXT／PDFのSource Type
- 文字数、PDFページ数、Parser
- SHA-256
- Snowflake Stage上の保存先

説明:

> 元ファイルをSnowflake Stageに保持し、PDFはCortex `AI_PARSE_DOCUMENT`でテキスト化します。抽出テキストだけでなく原本と来歴も残します。

## 1:25–2:05　Decision Pack生成

`Decision Pack`を開き、`Generate`を実行します。

4つのSectionを示します。

1. Governance
2. Value
3. Routing
4. Portfolio

1件を開き、以下を示します。

- `AI Draft`
- PriorityとRationale
- Structured detail
- Source evidence IDs

> Procedureは4 Sectionの欠落、不正なPriority、選択Runに属さないEvidence IDを拒否します。生成時点ではDraftです。

## 2:05–2:50　Human Review

4 Sectionを順に承認します。必要なら1件だけ`Edit before deciding`を示します。

確認点:

- `AI Draft`から`Human Reviewed`へ遷移
- Decision ActorとTimestamp
- 承認済み件数の増加
- Publish確認前はPublishボタンが無効

> Approveは人の判断を記録しますが、まだ正式記録にはしません。

## 2:50–3:20　明示的Publish

`Confirm publication of approved sections`へチェックし、`Publish`を実行します。

示す内容:

- `Published 4 decision(s)`
- `Published Governed Record`

> Publishは別の権限境界です。承認済みだけを正式記録にし、重複書込みと重複履歴を防ぎます。

## 3:20–3:45　Published／Portfolio

`Published`で4件のGoverned Decision Recordを示します。続けて`Portfolio`で以下を示します。

- Initiative
- Governance
- Value
- Recommendation
- Priority

## 3:45–4:00　Audit

`Audit trail`を開き、`APPROVE`と`PUBLISH`が別イベントとしてActor、Timestamp付きで残ることを示します。

締め:

> AIがEvidenceから提案し、人が判断し、Snowflakeが正式記録と判断履歴を保持する。ReadinessOpsはAI Initiativeを継続統制するValue Control Planeです。

## デモ時の注意

- `RUN_001`は使用・変更せず、`RUN_FINALIST_E2E_001`だけを使用する
- 不要な再生成を避け、既に成功したAgent Runを表示してもよい
- Live件数ではなく、状態遷移とTraceabilityを説明する
- 使用するEvidenceは小さな合成データに限定する

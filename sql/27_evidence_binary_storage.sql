-- ============================================================
-- Evidence original storage without Snowpark file APIs
-- ============================================================
-- Idempotent. Existing staged evidence remains valid; new uploads are stored
-- as immutable BINARY objects addressed by SHA-256.

USE SCHEMA APP;

CREATE TABLE IF NOT EXISTS EVIDENCE_ORIGINAL_OBJECT (
    CONTENT_SHA256        VARCHAR(64) NOT NULL,
    FILE_CONTENT          BINARY(67108864) NOT NULL,
    BYTE_COUNT            NUMBER(38,0) NOT NULL,
    MEDIA_TYPE            VARCHAR(100),
    FIRST_SOURCE_FILENAME VARCHAR(16777216),
    CREATED_AT            TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY            VARCHAR(200) DEFAULT CURRENT_USER()
);

SELECT
    'EVIDENCE_ORIGINAL_OBJECT_READY' AS TEST_NAME,
    COUNT(*) AS EXISTING_OBJECT_COUNT
FROM EVIDENCE_ORIGINAL_OBJECT;

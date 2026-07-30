#!/usr/bin/env python3
"""Final-Reviewer-governed engineering memory and policy promotion."""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sqlite3
import sys
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

MEMORY_TYPES = {
    "ARCHITECTURE_DECISION",
    "PRODUCT_DECISION",
    "BUG_ROOT_CAUSE",
    "ESCAPED_DEFECT",
    "VALIDATION_GAP",
    "RECOVERY_LESSON",
    "STABLE_FALSE_POSITIVE",
    "TOOLING_CONSTRAINT",
    "PROJECT_CONVENTION",
    "USER_APPROVED_PREFERENCE",
}
SEVERITIES = {"REJECT", "REQUIRE", "PREFER"}
TOPIC_KEY = re.compile(r"^[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*$")
HEX_HASH = re.compile(r"^[0-9a-f]{64}$")


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def fail(code: str, detail: str = "") -> None:
    payload = {"status": "ERROR", "code": code}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def connect(path: str) -> sqlite3.Connection:
    database = sqlite3.connect(path)
    database.row_factory = sqlite3.Row
    database.execute("PRAGMA foreign_keys=ON")
    database.execute("PRAGMA journal_mode=WAL")
    database.execute("PRAGMA busy_timeout=5000")
    return database


def initialize(database: sqlite3.Connection) -> None:
    database.executescript(
        """
        CREATE TABLE IF NOT EXISTS memories(
            memory_id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            task_id TEXT NOT NULL,
            topic_key TEXT NOT NULL,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            lesson TEXT NOT NULL,
            candidate_hash TEXT NOT NULL,
            evidence_hash TEXT NOT NULL,
            final_review_hash TEXT,
            status TEXT NOT NULL,
            revision INTEGER NOT NULL DEFAULT 1,
            supersedes TEXT,
            conflicts_with TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            review_after TEXT,
            UNIQUE(project_id, task_id, topic_key),
            FOREIGN KEY(supersedes) REFERENCES memories(memory_id)
        );
        CREATE INDEX IF NOT EXISTS memories_search
            ON memories(project_id, topic_key, title, status);
        CREATE TABLE IF NOT EXISTS policies(
            policy_id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            topic_key TEXT NOT NULL,
            severity TEXT NOT NULL,
            status TEXT NOT NULL,
            source_memory_ids TEXT NOT NULL,
            created_at TEXT NOT NULL,
            UNIQUE(project_id, topic_key)
        );
        """
    )
    database.commit()


def memory_row(database: sqlite3.Connection, memory_id: str) -> sqlite3.Row:
    row = database.execute("SELECT * FROM memories WHERE memory_id=?", (memory_id,)).fetchone()
    if row is None:
        fail("MEMORY_NOT_FOUND", memory_id)
    return row


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="governance-memory")
    subcommands = value.add_subparsers(dest="command", required=True)

    initialize_parser = subcommands.add_parser("init")
    initialize_parser.add_argument("--db", required=True)

    propose = subcommands.add_parser("propose")
    for name in (
        "db",
        "project-id",
        "task-id",
        "topic-key",
        "type",
        "title",
        "lesson",
        "candidate-hash",
        "evidence-hash",
    ):
        propose.add_argument(f"--{name}", required=True)
    propose.add_argument("--conflicts-with")

    adjudicate = subcommands.add_parser("adjudicate")
    adjudicate.add_argument("--db", required=True)
    adjudicate.add_argument("--memory-id", required=True)
    adjudicate.add_argument("--decision", required=True, choices=("APPROVE", "REJECT"))
    adjudicate.add_argument("--final-review-hash", required=True)
    adjudicate.add_argument("--review-after-days", type=int, default=90)

    search = subcommands.add_parser("search")
    search.add_argument("--db", required=True)
    search.add_argument("--project-id", required=True)
    search.add_argument("--query", required=True)
    search.add_argument("--limit", type=int, default=20)

    get = subcommands.add_parser("get")
    get.add_argument("--db", required=True)
    get.add_argument("--memory-id", required=True)

    review = subcommands.add_parser("review-due")
    review.add_argument("--db", required=True)
    review.add_argument("--project-id", required=True)

    promote = subcommands.add_parser("promote-policy")
    promote.add_argument("--db", required=True)
    promote.add_argument("--project-id", required=True)
    promote.add_argument("--topic-key", required=True)
    promote.add_argument("--severity", required=True, choices=sorted(SEVERITIES))
    promote.add_argument("--owner-authorized", required=True, choices=("true", "false"))
    return value


def main() -> None:
    args = parser().parse_args()
    database = connect(args.db)
    initialize(database)

    if args.command == "init":
        print(json.dumps({"status": "MEMORY_STORE_READY"}, sort_keys=True))
        return

    if args.command == "propose":
        if args.type not in MEMORY_TYPES:
            fail("INVALID_MEMORY_TYPE", args.type)
        if TOPIC_KEY.fullmatch(args.topic_key) is None:
            fail("INVALID_TOPIC_KEY", args.topic_key)
        if HEX_HASH.fullmatch(args.candidate_hash) is None:
            fail("INVALID_HASH", "candidate_hash")
        if HEX_HASH.fullmatch(args.evidence_hash) is None:
            fail("INVALID_HASH", "evidence_hash")
        if args.conflicts_with:
            active = database.execute(
                "SELECT 1 FROM memories WHERE memory_id=? AND status='ACTIVE'",
                (args.conflicts_with,),
            ).fetchone()
            if active is None:
                fail("CONFLICT_TARGET_NOT_ACTIVE", args.conflicts_with)
        memory_id = "mem-" + uuid.uuid4().hex
        timestamp = now()
        try:
            database.execute(
                """
                INSERT INTO memories(
                    memory_id, project_id, task_id, topic_key, type, title, lesson,
                    candidate_hash, evidence_hash, final_review_hash, status,
                    conflicts_with, created_at, updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    memory_id,
                    args.project_id,
                    args.task_id,
                    args.topic_key,
                    args.type,
                    args.title,
                    args.lesson,
                    args.candidate_hash,
                    args.evidence_hash,
                    None,
                    "CANDIDATE",
                    args.conflicts_with,
                    timestamp,
                    timestamp,
                ),
            )
            database.commit()
        except sqlite3.IntegrityError as exc:
            fail("DUPLICATE_MEMORY_CANDIDATE", str(exc))
        print(json.dumps({"status": "MEMORY_CANDIDATE", "memory_id": memory_id}, sort_keys=True))
        return

    if args.command == "adjudicate":
        if HEX_HASH.fullmatch(args.final_review_hash) is None:
            fail("INVALID_HASH", "final_review_hash")
        row = memory_row(database, args.memory_id)
        if row["status"] != "CANDIDATE":
            fail("MEMORY_NOT_CANDIDATE", row["status"])
        if args.decision == "REJECT":
            database.execute(
                "UPDATE memories SET status='REJECTED', final_review_hash=?, updated_at=? WHERE memory_id=?",
                (args.final_review_hash, now(), args.memory_id),
            )
            database.commit()
            print(json.dumps({"status": "MEMORY_REJECTED", "memory_id": args.memory_id}, sort_keys=True))
            return

        previous = database.execute(
            """
            SELECT * FROM memories
            WHERE project_id=? AND topic_key=? AND status='ACTIVE'
            ORDER BY updated_at DESC LIMIT 1
            """,
            (row["project_id"], row["topic_key"]),
        ).fetchone()
        revision = previous["revision"] + 1 if previous else 1
        if previous:
            database.execute(
                "UPDATE memories SET status='SUPERSEDED', updated_at=? WHERE memory_id=?",
                (now(), previous["memory_id"]),
            )
        review_after = (
            datetime.now(timezone.utc) + timedelta(days=max(1, args.review_after_days))
        ).isoformat()
        database.execute(
            """
            UPDATE memories
            SET status='ACTIVE', final_review_hash=?, revision=?, supersedes=?,
                review_after=?, updated_at=?
            WHERE memory_id=?
            """,
            (
                args.final_review_hash,
                revision,
                previous["memory_id"] if previous else None,
                review_after,
                now(),
                args.memory_id,
            ),
        )
        database.commit()
        print(
            json.dumps(
                {
                    "status": "MEMORY_ACTIVE",
                    "memory_id": args.memory_id,
                    "revision": revision,
                    "supersedes": previous["memory_id"] if previous else None,
                },
                sort_keys=True,
            )
        )
        return

    if args.command == "search":
        query = "%" + args.query.lower() + "%"
        rows = database.execute(
            """
            SELECT memory_id, topic_key, type, title, status, revision,
                   review_after, updated_at
            FROM memories
            WHERE project_id=? AND (lower(topic_key) LIKE ? OR lower(title) LIKE ?)
            ORDER BY CASE status WHEN 'ACTIVE' THEN 0 WHEN 'CANDIDATE' THEN 1 ELSE 2 END,
                     updated_at DESC
            LIMIT ?
            """,
            (args.project_id, query, query, max(1, min(args.limit, 100))),
        ).fetchall()
        print(
            json.dumps(
                {
                    "schema": "opencode-governance.memory-search/v1",
                    "disclosure_layer": 1,
                    "results": [dict(row) for row in rows],
                },
                sort_keys=True,
            )
        )
        return

    if args.command == "get":
        print(json.dumps(dict(memory_row(database, args.memory_id)), sort_keys=True))
        return

    if args.command == "review-due":
        rows = database.execute(
            """
            SELECT memory_id, topic_key, title, review_after
            FROM memories
            WHERE project_id=? AND status='ACTIVE' AND review_after<=?
            ORDER BY review_after
            """,
            (args.project_id, now()),
        ).fetchall()
        print(json.dumps({"status": "MEMORY_REVIEW", "results": [dict(row) for row in rows]}, sort_keys=True))
        return

    if args.owner_authorized != "true":
        fail("OWNER_AUTHORIZATION_REQUIRED")
    rows = database.execute(
        """
        SELECT memory_id, task_id
        FROM memories
        WHERE project_id=? AND topic_key=? AND final_review_hash IS NOT NULL
          AND status IN ('ACTIVE','SUPERSEDED')
        ORDER BY updated_at
        """,
        (args.project_id, args.topic_key),
    ).fetchall()
    if len({row["task_id"] for row in rows}) < 2:
        fail("INSUFFICIENT_VALIDATED_OCCURRENCES")
    policy_id = "policy-" + uuid.uuid4().hex
    try:
        database.execute(
            """
            INSERT INTO policies(
                policy_id, project_id, topic_key, severity, status,
                source_memory_ids, created_at
            ) VALUES(?,?,?,?,?,?,?)
            """,
            (
                policy_id,
                args.project_id,
                args.topic_key,
                args.severity,
                "ACTIVE_PROJECT_RULE",
                json.dumps([row["memory_id"] for row in rows]),
                now(),
            ),
        )
        database.commit()
    except sqlite3.IntegrityError:
        fail("POLICY_ALREADY_EXISTS")
    print(
        json.dumps(
            {
                "policy_id": policy_id,
                "project_id": args.project_id,
                "topic_key": args.topic_key,
                "severity": args.severity,
                "status": "ACTIVE_PROJECT_RULE",
                "source_memory_ids": [row["memory_id"] for row in rows],
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()

-- BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS "contacts" (
	"db_id"	INTEGER NOT NULL UNIQUE,
	"peer_id"	TEXT NOT NULL,
	"avatar"	TEXT,
	"name"	TEXT NOT NULL,
	PRIMARY KEY("db_id" AUTOINCREMENT)
);
CREATE TABLE IF NOT EXISTS "profiles" (
	"db_id"	INTEGER NOT NULL UNIQUE,
	"peer_id"	TEXT NOT NULL,
	"private_key"	TEXT NOT NULL,
	"avatar"	TEXT,
	"name"	TEXT NOT NULL,
	PRIMARY KEY("db_id" AUTOINCREMENT)
);
CREATE TABLE IF NOT EXISTS "threads" (
	"db_id"	INTEGER NOT NULL UNIQUE,
	"profile_db_id"	INTEGER NOT NULL,
	"contact_db_id"	INTEGER NOT NULL,

	-- TODO
	-- Unix timestamp with milliseconds added in time of thread creation.
	-- "creation_timestamp"	INTEGER NOT NULL,

	-- Unix timestamp with milliseconds that represents the most fresh change (creation_timestamp or last message creation_timestamp).
	"last_update"	INTEGER NOT NULL,
	
	"last_message_db_id"	INTEGER,
	"first_new_message_db_id"	INTEGER,
	"new_messages_count"	INTEGER NOT NULL,
	"first_unseen_message_by_contact_db_id"	INTEGER,
	
	PRIMARY KEY("db_id" AUTOINCREMENT)
	FOREIGN KEY ("profile_db_id") REFERENCES "profiles" ("db_id") ON DELETE CASCADE,
    FOREIGN KEY ("contact_db_id") REFERENCES "contacts" ("db_id") ON DELETE CASCADE,
    FOREIGN KEY ("last_message_db_id") REFERENCES "messages" ("db_id"),
	FOREIGN KEY ("first_new_message_db_id") REFERENCES "messages" ("db_id"),
    FOREIGN KEY ("first_unseen_message_by_contact_db_id") REFERENCES "messages" ("db_id")
);
CREATE TABLE IF NOT EXISTS "messages" (
	"db_id"	INTEGER NOT NULL UNIQUE,
	"thread_db_id"	INTEGER NOT NULL,
	"sender_db_id"	INTEGER,
	"creation_timestamp"	INTEGER NOT NULL,
	"type"	TEXT NOT NULL,
	"file"	TEXT,
	"text"	TEXT,
	"markdown"	INTEGER,
	PRIMARY KEY("db_id" AUTOINCREMENT)
	FOREIGN KEY ("thread_db_id") REFERENCES "threads" ("db_id") ON DELETE CASCADE,
    FOREIGN KEY ("sender_db_id") REFERENCES "contacts" ("db_id")
);

/*
unfortunately in sqlite there are no DECLARE, WITH UPDATE, CREATE FUNCTION, etc. especially in triggers.
so we should use subqueries what is inefficient.
TODO optimize triggers 
	- replace logic to app?
	- implement FOR EACH STATEMENT
*/

CREATE TRIGGER message_deletion
BEFORE DELETE ON messages
FOR EACH ROW
BEGIN
	-- if last message
	UPDATE threads
	SET
		last_message_db_id = (
			SELECT MAX(db_id)
			FROM messages
			WHERE thread_db_id = OLD.thread_db_id AND db_id != OLD.db_id
			ORDER BY creation_timestamp DESC
			LIMIT 1
		),
		last_update = (
			SELECT CASE WHEN (
				SELECT MAX(db_id)
				FROM messages
				WHERE thread_db_id = OLD.thread_db_id AND db_id != OLD.db_id
				ORDER BY creation_timestamp DESC
				LIMIT 1
			) IS NULL THEN
				0 -- TODO threads creation_timestamp
			ELSE (
				SELECT MAX(creation_timestamp)
				FROM messages
				WHERE thread_db_id = OLD.thread_db_id AND db_id != OLD.db_id
				ORDER BY creation_timestamp DESC
				LIMIT 1
			)
			END
		)
	WHERE db_id = OLD.thread_db_id AND last_message_db_id = OLD.db_id;

	-- if one of new messages
	UPDATE threads
	SET new_messages_count = new_messages_count - 1,
	first_new_message_db_id = (
		CASE WHEN (SELECT first_new_message_db_id FROM threads WHERE db_id = OLD.thread_db_id) = OLD.db_id
		THEN (
			SELECT MAX(db_id)
			FROM messages
			WHERE thread_db_id = OLD.thread_db_id
				AND db_id != OLD.db_id
				AND creation_timestamp >= OLD.creation_timestamp
				AND sender_db_id IS NOT NULL
			ORDER BY creation_timestamp
			LIMIT 1
		)
		ELSE (SELECT first_new_message_db_id FROM threads WHERE db_id = OLD.thread_db_id) END -- TODO
	)
	WHERE db_id = OLD.thread_db_id
		AND first_new_message_db_id IS NOT NULL
		AND ( -- if message is not older then first_new_message
			SELECT m.creation_timestamp
			FROM messages m
			JOIN threads t ON m.thread_db_id = t.db_id
			WHERE t.db_id = OLD.thread_db_id AND m.db_id = t.first_new_message_db_id
		) >= OLD.creation_timestamp;

	-- if one of unseen messages
	UPDATE threads
	SET first_unseen_message_by_contact_db_id = (
		SELECT MAX(db_id)
		FROM messages
		WHERE creation_timestamp > OLD.creation_timestamp AND OLD.sender_db_id IS NULL
		ORDER BY creation_timestamp
		LIMIT 1
	)
	WHERE db_id = OLD.thread_db_id AND first_unseen_message_by_contact_db_id = OLD.db_id;
END;


-- TODO check for right creation_timestamp in case of, lets say, sync
CREATE TRIGGER message_creation
AFTER INSERT ON messages
FOR EACH ROW
BEGIN
	UPDATE threads
	SET
		last_message_db_id = NEW.db_id,
		last_update = NEW.creation_timestamp,
		first_new_message_db_id = (
			CASE 

			-- when there were new messages and new message is from us
			WHEN first_new_message_db_id IS NOT NULL AND NEW.sender_db_id IS NULL
			THEN NULL -- reset to NULL

			-- when there were no new messages and new message is from contact
			WHEN first_new_message_db_id IS NULL AND NEW.sender_db_id IS NOT NULL
			THEN NEW.db_id -- set as this new message

			/*
				when there were new messages and new message is from contact
				OR
				when there were no new messages and new message is from us
			*/
			ELSE first_new_message_db_id

			END
		),
		new_messages_count = (
			CASE WHEN NEW.sender_db_id IS NULL
			THEN 0
			ELSE new_messages_count + 1
			END
		),
		first_unseen_message_by_contact_db_id = (
			CASE 

			-- when there were no unseen messages and new message is from us
			WHEN first_unseen_message_by_contact_db_id IS NULL AND NEW.sender_db_id IS NULL
			THEN NEW.db_id -- set as this new message

			-- when there were unseen messages and new message is from contact
			WHEN first_unseen_message_by_contact_db_id IS NOT NULL AND NEW.sender_db_id IS NOT NULL
			THEN NULL -- reset to NULL

			/*
				when there were no unseen messages and new message is from contact
				OR
				when there were unseen messages and new message is from us
			*/
			ELSE first_unseen_message_by_contact_db_id -- do not change

			END
		)
	WHERE db_id = NEW.thread_db_id;
END;

-- COMMIT;

-- Initial schema v1
DROP TABLE IF EXISTS users;

CREATE TABLE
    users (
        id SERIAL PRIMARY KEY,
        email VARCHAR(255) NOT NULL UNIQUE,
        first_name VARCHAR(100),
        last_name VARCHAR(100),
        created_at TIMESTAMP DEFAULT NOW ()
    );

INSERT INTO
    users (email, first_name, last_name)
values
    ('alice@example.com', 'Alice', 'Anderson'),
    ('bob@example.com', 'Bob', 'Brown'),
    ('charlie@example.com', 'Charlie', 'Clark');
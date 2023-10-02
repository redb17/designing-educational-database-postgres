-- ADD TSVECTOR FUNCTION
CREATE OR REPLACE FUNCTION fn_add_tsvector() RETURNS TRIGGER AS $$
BEGIN
  NEW.text_vector := to_tsvector('english', NEW.text_description);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- STUDENTS RELATION
CREATE TABLE students (
    student_id SERIAL PRIMARY KEY,
    student_name VARCHAR(100) NOT NULL,
    gender CHAR(1) CONSTRAINT gender_constraint CHECK (gender in ('M', 'F')),
    phone VARCHAR(30),
    place VARCHAR(20) NOT NULL, -- city/state to find the trend in that place
    addr TEXT
);

CREATE INDEX idx_gin_place_country ON students USING BTREE(place);

-- EXAMS RELATION
CREATE TABLE exams (
    exam_id SERIAL PRIMARY KEY,
    exam_name TEXT NOT NULL
);

-- SUBJECTS RELATION
CREATE TABLE subjects (
    subject_id SERIAL PRIMARY KEY,
    subject_name VARCHAR(100) NOT NULL
);

-- CHAPTERS RELATION
CREATE TABLE chapters (
    chapter_id INTEGER PRIMARY KEY,
    chapter_name VARCHAR(100) NOT NULL,
    subject_id INTEGER REFERENCES subjects (subject_id) -- many to one relation with `subjects`
);

-- ANSWERS RELATION
CREATE TABLE answers (
    answer_id SERIAL PRIMARY KEY,
    text_description TEXT NOT NULL,
    text_vector TSVECTOR
);

CREATE TRIGGER tr_add_tsvector_answers
BEFORE INSERT ON answers
FOR EACH ROW
EXECUTE FUNCTION fn_add_tsvector();

CREATE INDEX idx_gin_text_vector_answers ON answers USING GIN(text_vector);

-- QUESTIONS RELATION
CREATE TABLE questions (
    question_id SERIAL PRIMARY KEY,
    text_description TEXT NOT NULL,
    text_vector TSVECTOR,
    answer_option_1 INTEGER REFERENCES answers (answer_id), -- many to many relation with `answers`
    answer_option_2 INTEGER REFERENCES answers (answer_id),
    answer_option_3 INTEGER REFERENCES answers (answer_id),
    answer_option_correct INTEGER REFERENCES answers (answer_id), -- many to one relation with `answers`
    chapter_id INTEGER REFERENCES chapters (chapter_id) -- many to one relation with `chapters`
);

CREATE TRIGGER tr_add_tsvector_questions
BEFORE INSERT ON questions
FOR EACH ROW
EXECUTE FUNCTION fn_add_tsvector();

CREATE INDEX tr_add_tsvector_questions ON answers USING GIN(text_vector);

-- EVENTS RELATION
CREATE TABLE events (
    event_code CHAR(10) UNIQUE NOT NULL,
    text_description TEXT NOT NULL,
    text_vector TSVECTOR,
    total_questions INTEGER NOT NULL CONSTRAINT positive_val_constraint CHECK (total_questions > 0),
    min_corrects INTEGER NOT NULL CONSTRAINT min_corrects_constraint CHECK (min_corrects BETWEEN 0 AND total_questions)
);

CREATE TRIGGER tr_add_tsvector_events
BEFORE INSERT ON events
FOR EACH ROW
EXECUTE FUNCTION fn_add_tsvector();

CREATE INDEX tr_add_tsvector_events ON answers USING GIN(text_vector);

CREATE TABLE attempts (
    attempt_id SERIAL,
    attempt_ts TIMESTAMP NOT NULL,
    attempt_dt DATE,
    student_id INTEGER REFERENCES students (student_id), -- many to one relation with `students`
    question_id INTEGER REFERENCES questions (question_id), -- many to one relation with `questions`
    exam_id INTEGER REFERENCES exams (exam_id), -- many to one relation with `exams`
    selected_answer_id INTEGER REFERENCES answers (answer_id), -- many to one relation with `answers`
    event_code CHAR(10) REFERENCES events (event_code), -- many to one relation with `events`
    PRIMARY KEY (attempt_id, attempt_dt)
)
PARTITION BY RANGE(attempt_dt);

CREATE OR REPLACE FUNCTION create_partitions(target_year integer) 
RETURNS void AS 
$$
DECLARE
    start_date date := DATE(target_year || '-01-01');
    end_date date := DATE(target_year || '-12-31');
    current_dt date := start_date;
    partition_name text;
	tomorrow_dt date;
BEGIN
    WHILE current_dt <= end_date LOOP
        partition_name := 'attempts_' || to_char(current_dt, 'YYYY_MM_DD');
        tomorrow_dt := current_dt + 1;
		execute format ('
			create table if not exists %s
			partition of attempts
			for values from (''%s'') to (''%s'');
		', partition_name, current_dt, tomorrow_dt);

		current_dt := current_dt + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- HAS TO BE EXECUTED BEFORE THE STARTING OF THE NEXT YEAR
SELECT create_partitions(2023);

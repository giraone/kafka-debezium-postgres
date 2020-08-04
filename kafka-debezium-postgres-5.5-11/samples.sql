DROP TABLE public.student;

CREATE TABLE public.student
(
    name character varying(255),
    email character varying(255),    
    modified TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT student_pkey PRIMARY KEY (name)
);

ALTER TABLE public.student REPLICA IDENTITY FULL;

DROP TABLE public.outbox;

CREATE TABLE public.outbox
(
    id uuid not null,
    aggregatetype character varying(255),
    major_version smallint not null,
    minor_version smallint not null,
    aggregateid character varying(255),
    payload jsonb,
    added timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT outbox_pkey PRIMARY KEY (id)
);

ALTER TABLE public.outbox REPLICA IDENTITY FULL;

INSERT INTO public.outbox VALUES('00000000-dead-cafe-ffff-111111111111', 'student', 1, 0, 'Teacher', '{ "name": "Teacher", "email": "teacher@gmail.com" }');

SELECT * FROM public.outbox;

INSERT INTO public.student(NAME, EMAIL) VALUES('Jack','jack@gmail.com');
INSERT INTO public.student(NAME, EMAIL) VALUES('Jim','jim@gmail.com');
INSERT INTO public.student(NAME, EMAIL) VALUES('Peter','peter@gmail.com');

INSERT INTO public.outbox VALUES('00000001-dead-cafe-ffff-111111111111', 'student', 1, 0, 'Jack', '{ "name": "Jack", "email": "jack@gmail.com" }');
INSERT INTO public.outbox VALUES('00000002-dead-cafe-ffff-111111111111', 'student', 1, 0, 'Jim', '{ "name": "Jim", "email": "jim@gmail.com" }');
INSERT INTO public.outbox VALUES('00000003-dead-cafe-ffff-111111111111', 'student', 1, 0, 'Peter', '{ "name": "Peter", "email": "peter@gmail.com" }');
INSERT INTO public.outbox VALUES('00000004-dead-cafe-ffff-111111111111', 'student', 1, 0, 'Will', '{ "name": "Will", "email": "will@gmail.com" }');
INSERT INTO public.outbox VALUES('00000005-dead-cafe-ffff-111111111111', 'student', 1, 0, 'Mike', '{ "name": "Mike", "email": "mike@gmail.com" }');


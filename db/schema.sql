CREATE TABLE games(id integer primary key asc, started_at, finished_at, abandoned boolean);
CREATE TABLE players(id integer primary key asc, slack_id, username);
CREATE TABLE participates(id integer primary key asc, game_id, player_id, win boolean);

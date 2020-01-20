CREATE DATABASE hub;
CREATE USER hubdbadmin WITH encrypted password 'changeme';
GRANT all privileges ON database hub to hubdbadmin;

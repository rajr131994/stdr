# README

## Docker
When running the SAP connector backend in docker for the first time, you must complete the following one time only:
* ``docker-compose build``
* ``docker-compose run sap bundle exec rake app:update:bin``
* Add the master key for the repo in the config/master.key file. Get this from one of the current developers. This key is super secret and used in production for decrypting sensitive information! It must not be shared or pushed to git!
* ``docker-compose run sap bundle exec rails db:create db:migrate``

On all subsequent executions you need to run:
* ``docker-compose up``

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

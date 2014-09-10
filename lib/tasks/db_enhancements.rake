####### Important information ####################
# This file is used to setup a shared extensions #
# within a dedicated schema. This gives us the   #
# advantage of only needing to enable extensions #
# in one place.                                  #
#                                                #
# This task should be run AFTER db:create but    #
# BEFORE db:migrate.                             #
##################################################


namespace :db do
  desc 'Also create shared extensions schemas'
  task :extensions => :environment do
    # Create PostGIS extension
    # Rake::Task["db:gis:setup"].invoke
    if Rails.env.development?
      ActiveRecord::Base.connection.execute 'CREATE SCHEMA IF NOT EXISTS postgis;'
      ActiveRecord::Base.connection.execute 'CREATE EXTENSION IF NOT EXISTS postgis SCHEMA postgis;'
    end
  end
end

Rake::Task["db:create"].enhance do
  Rake::Task["db:extensions"].invoke
end

Rake::Task["db:drop"].enhance do
  Ekylibre::Tenant.clear!
end

Rake::Task["db:test:purge"].enhance do
  Rake::Task["db:extensions"].invoke
end

require 'rails'

module ActsAsSolr
  class Railtie < Rails::Railtie
    rake_tasks do
      load "#{File.dirname __FILE__}/../tasks/solr.rake"
    end
  end
end

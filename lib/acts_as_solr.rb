require 'active_record'
require 'rexml/document'
require 'net/http'
require 'yaml'
require 'time'
require 'erb'
require 'rexml/xpath'

require_relative 'solr'
require_relative 'acts_as_solr/railtie'
require_relative 'acts_as_solr/acts_methods'
require_relative 'acts_as_solr/common_methods'
require_relative 'acts_as_solr/parser_methods'
require_relative 'acts_as_solr/class_methods'
require_relative 'acts_as_solr/dynamic_attribute'
require_relative 'acts_as_solr/local'
require_relative 'acts_as_solr/instance_methods'
require_relative 'acts_as_solr/common_methods'
require_relative 'acts_as_solr/deprecation'
require_relative 'acts_as_solr/search_results'
require_relative 'acts_as_solr/lazy_document'
require_relative 'acts_as_solr/mongo_mapper'
require_relative 'acts_as_solr/post'
require_relative 'acts_as_solr/scope_with_applied_names'

# reopen ActiveRecord and include the acts_as_solr method
ActiveRecord::Base.extend ActsAsSolr::ActsMethods

module ActsAsSolr

  # this disable commits as the server is configured to do autocommits
  mattr_accessor :near_real_time_search
  self.near_real_time_search = true


end

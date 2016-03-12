namespace :solr do

  APACHE_MIRROR = ENV['APACHE_MIRROR'] || "https://archive.apache.org/dist"
  SOLR_VERSION = '5.0.0'
  SOLR_FILENAME = "solr-#{SOLR_VERSION}.tgz"
  SOLR_MD5SUM = '9458fda5e876b3ada34f4bd680e15ea7'
  SOLR_URL = "#{APACHE_MIRROR}/lucene/solr/#{SOLR_VERSION}/#{SOLR_FILENAME}"
  SOLR_DIR = "solr-#{SOLR_VERSION}"

  require File.expand_path "#{File.dirname __FILE__}/../../config/solr_environment"

  def solr_downloaded?
    File.exists? "#{SOLR_PATH}/server/start.jar"
  end

  desc "Download and install Solr+Jetty #{SOLR_VERSION}."
  task :download do
    abort 'Solr already downloaded.' if solr_downloaded?

    tmpdir = [ '/var/tmp', '/tmp' ].find { |d| File.exists?(d) }
    Dir.chdir tmpdir do
      skip_download = false
      if File.exists?(SOLR_FILENAME)
        sh "echo \"#{SOLR_MD5SUM}  #{SOLR_FILENAME}\" | md5sum -c -" do |ok, res|
          skip_download = ok
        end
      end

      unless skip_download
        sh "wget -c #{SOLR_URL}"
      end

      sh "echo \"#{SOLR_MD5SUM}  #{SOLR_FILENAME}\" | md5sum -c -" do |ok, res|
        abort "MD5SUM do not match" if !ok

        sh "tar xzf #{SOLR_FILENAME} -C /tmp"

        cd "/tmp/#{SOLR_DIR}"
        mkdir_p SOLR_PATH
        cp_r %w[bin contrib dist server], SOLR_PATH, verbose: true
        rm_rf "/tmp/#{SOLR_DIR}"
      end
    end
  end

  desc 'Remove Solr instalation from the tree.'
  task :remove do
    rm_rf %w[bin contrib dist server].map{ |i| File.join SOLR_PATH, i }, verbose: true
  end

  desc 'Update to the newest supported version of solr'
  task update: [:remove, :download] do
  end

  desc 'Starts Solr. Options accepted: RAILS_ENV=your_env, PORT=XX. Defaults to development if none.'
  task :start do
    if !solr_downloaded?
      puts "ERROR: Can't find Solr on the source code! Please run 'rake solr:download'."
      abort
    end

    FileUtils.mkdir_p SOLR_LOGS_PATH
    FileUtils.mkdir_p SOLR_PIDS_PATH
    FileUtils.mkdir_p SOLR_DATA_PATH
    FileUtils.mkdir_p SOLR_CORE_PATH

    Dir["#{ACTS_AS_SOLR_ROOT}/solr/solr.xml"].each do |file|
      ln_sf file, SOLR_DATA_PATH, verbose: false
    end
    Dir["#{ACTS_AS_SOLR_CORE_PATH}/{conf,core.properties}"].each do |file|
      ln_sf file, SOLR_CORE_PATH, verbose: false
    end

    # test if there is a solr already running
    begin
      n = Net::HTTP.new '127.0.0.1', SOLR_PORT
      n.request_head('/').value

    rescue Net::HTTPServerException #responding
      puts "Port #{SOLR_PORT} in use" and return

    rescue Errno::ECONNREFUSED, Errno::EBADF, NoMethodError #not responding
      # there's an issue with Net::HTTP.request where @socket is nil and raises a NoMethodError
      # http://redmine.ruby-lang.org/issues/show/2708
      Dir.chdir(SOLR_PATH) do
        cmd = <<-CMD
bin/solr start #{SOLR_OPTIONS} -a "-Djetty.logs=#{SOLR_LOGS_PATH},jetty.port=#{SOLR_PORT}" -s "#{SOLR_DATA_PATH}" -h "#{SOLR_HOST}" -p #{SOLR_PORT} -d #{SOLR_SERVER_PATH}
        CMD
        puts cmd

        windows = RUBY_PLATFORM =~ /(win|w)32$/
        if windows
          exec cmd
        else
          pid = fork do
            Process.setpgrp
            STDERR.close
            exec cmd
          end
        end

        File.write SOLR_PID_FILE, pid unless windows
        puts "#{ENV['RAILS_ENV']} Solr started successfully on #{SOLR_HOST}:#{SOLR_PORT}, pid: #{pid}."
      end
    end
  end

  desc 'Stops Solr. Specify the environment by using: RAILS_ENV=your_env. Defaults to development if none.'
  task :stop do

    if File.exists?(SOLR_PID_FILE)
      killed = false
      File.open(SOLR_PID_FILE, "r") do |f|
        pid = f.readline
        begin
          Process.kill('TERM', -pid.to_i)
          sleep 3
          killed = true
        rescue
          puts "Solr could not be found at pid #{pid.to_i}. Removing pid file."
        end
      end
      File.unlink(SOLR_PID_FILE)
      puts "Solr shutdown successfully." if killed
    else
      puts "PID file not found at #{SOLR_PID_FILE}. Either Solr is not running or no PID file was written."
    end
  end

  desc 'Restart Solr. Specify the environment by using: RAILS_ENV=your_env. Defaults to development if none.'
  task :restart do
    Rake::Task["solr:stop"].invoke
    Rake::Task["solr:start"].invoke
  end

  desc 'Remove Solr index'
  task destroy_index: :environment do

    raise "In production mode.  I'm not going to delete the index, sorry." if ENV['RAILS_ENV'] == "production"
    if File.exists?("#{SOLR_DATA_PATH}")
      Dir["#{SOLR_DATA_PATH}/index/*"].each{|f| File.unlink(f) if File.exists?(f)}
      Dir.rmdir("#{SOLR_DATA_PATH}/index")
      puts "Index files removed under " + ENV['RAILS_ENV'] + " environment"
    end
  end

  # this task is by Henrik Nyh
  # http://henrik.nyh.se/2007/06/rake-task-to-reindex-models-for-acts_as_solr
  desc %{Reindexes data for all acts_as_solr models. Clears index first to get rid of orphaned records and optimizes index afterwards. RAILS_ENV=your_env to set environment. ONLY=book,person,magazine to only reindex those models; EXCEPT=book,magazine to exclude those models. START_SERVER=true to solr:start before and solr:stop after. BATCH=123 to post/commit in batches of that size: default is 300. CLEAR=false to not clear the index first; OPTIMIZE=false to not optimize the index afterwards.}
  task reindex: :environment do

    delayed_job  = env_to_bool('DELAYED_JOB', false)
    optimize     = env_to_bool('OPTIMIZE', false)
    start_server = env_to_bool('START_SERVER', false)
    offset       = ENV['OFFSET'].to_i.nonzero? || 0
    clear_first  = env_to_bool('CLEAR', offset == 0)
    batch_size   = ENV['BATCH'].to_i.nonzero? || 300
    debug_output = env_to_bool("DEBUG", false)
    models       = (ENV['MODELS'] || '').split(',').map{ |m| m.constantize }
    threads      = (ENV['THREADS'] || '2').to_i

    logger = ActiveRecord::Base.logger = Logger.new(STDOUT)
    logger.level = ActiveSupport::Logger::INFO unless debug_output #logger level: info

    if start_server
      puts "Starting Solr server..."
      Rake::Task["solr:start"].invoke
    end

    # Disable optimize and commit
    module ActsAsSolr::CommonMethods
      def blank() end
      alias_method :deferred_solr_optimize, :solr_optimize
      alias_method :solr_optimize, :blank
      alias_method :solr_commit, :blank
    end

    models = $solr_indexed_models unless models.count > 0
    puts "Reindexing #{models.join ', '}..."
    models.each do |model|
      if clear_first
        puts "Clearing index for #{model}..."
        ActsAsSolr::Post.execute(Solr::Request::Delete.new(query: "#{model.solr_configuration[:type_field]}:#{model.name.gsub ':', "\\:"}"))
        ActsAsSolr::Post.execute(Solr::Request::Commit.new)
      end

      puts "Rebuilding index for #{model}..."
      model.rebuild_solr_index batch_size, offset: offset, threads: threads, delayed_job: delayed_job
      puts "Commiting changes..."
      ActsAsSolr::Post.execute(Solr::Request::Commit.new)
    end

    if $solr_indexed_models.empty?
      puts "There were no models to reindex."
    elsif optimize
      puts "Optimizing..."
      models.last.deferred_solr_optimize
    end

  end

  def env_to_bool(env, default)
    env = ENV[env] || ''
    case env
      when /^true$/i then true
      when /^false$/i then false
      else default
    end
  end

end


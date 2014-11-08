set :application, "app-name"
set :current_path, "#{application}"

default_run_options[:pty] = true

set :scm, :git

role :web, ""                          # Your HTTP server, Apache/etc
role :app, ""                   # This may be the same as your `Web` server

namespace :deploy do
  
  set(:user) do
    Capistrano::CLI.ui.ask("Enter user: ")
  end
  
  set(:commit_msg) do
    Capistrano::CLI.ui.ask("Enter commit message, or default => ") {|q| 
      q.default = "General Updates on #{DateTime.now.strftime("%m/%d/%Y %H:%I:%S")}"
    }
  end
  
  desc "Running update"
  task :update do
    transaction do
      commit_code
      update_code
      restart
    end
  end
  
  desc "Continue deploy if error occurred"
  task :staging do
    update_code
    restart
  end
  
  task :commit_code, :except => { :no_release => true } do
    run_locally "git add ."
    run_locally "git commit -m '#{commit_msg}'"
    run_locally "git push origin master"
  end

  task :update_code, :except => { :no_release => true } do
    run "cd #{current_path} && git reset --hard && git pull"
  end
  
  desc "Restarting mod_rails with restart.txt"
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "touch #{current_path}/tmp/restart.txt"
  end

  [:start, :stop, :check, :setup].each do |t|
    desc "#{t} task is a no-op with mod_rails"
    task t, :roles => :app do ; end
  end
end

namespace :gems do
  set(:unpack_gems) do
    Capistrano::CLI.ui.ask("What gems? ")
  end
  
  task :libify do 
    unpack
    move
    cleanup
  end
  
  task :unpack do
    puts "  * checking for vendor directory"
    run_locally "if [[ ! -d ./vendor ]]; then mkdir ./vendor; fi"
    for g in unpack_gems.strip.split(" ") do
      run_locally "gem unpack --target=./vendor/ #{g}"
    end
  end
  
  task :move do
    run_locally "for D in `find ./vendor/* -type d -depth 0`; do LIB=\"./$D/lib\"; if [[ -d $LIB ]]; then cp -R $LIB/* ./lib/; fi; done"
  end
  
  task :cleanup do
    run_locally "rm -rf ./vendor"
  end
end

#!/usr/bin/env ruby

$:.unshift File.join(File.dirname(__FILE__), *%w[.. lib])

require 'rubygems'
require 'rubygems/specification'
require 'sinatra'
require 'timeout'
require 'yaml'
require 'net/http'
require 'json'
require 'digest'

def log(message)
  @existing_output = [] unless @existing_output
  @existing_output << message
  return @existing_output.join("\n")
end

get '/' do
  "Codebase Gem Builder."
end

post '/' do
  ## Get the payload from Codebase
  payload = params[:payload]
  payload = JSON::parse(payload)
  log "-> Got Payload for: #{payload['repository']['clone_url']}"
  
  
  unless payload['repository'] && payload['repository']['clone_url']
    return log(" !! No Clone URL for this repository was found.")
  end
  
  ## Look for a gemspec in this push, if it's changed, we can generate otherwise, move along.
  has_gemspec = false
  for commit in payload["commits"]
    files = [commit['added'], commit['modified']].flatten.uniq.join(" ") rescue []
    if files.match(/gemspec/)
      has_gemspec = true
      log "-> Found a gemspec in one of these commits"
    end
  end
  
  if has_gemspec == false
    return log("!! No gemspec found in this push. Move along now.")
  end
  
  ## Identifer for this repository
  repo_id = Digest::SHA1.hexdigest(payload['repository']['clone_url'])
  log("-> Repository has ID of '#{repo_id}'")
  ## Make directory to store this in
  system("mkdir -p tmp/#{repo_id}")
  if File.exist?("tmp/#{repo_id}/.git")
    previous_head = `cd tmp/#{repo_id} && git rev-list master --`.split("\n").first[0,6] rescue '000000'
    system("cd tmp/#{repo_id} && git pull origin master")
    new_head = `cd tmp/#{repo_id} && git rev-list master --`.split("\n").first[0,6] rescue '000000'
    log("-> Fetched latest version of repository. #{previous_head} -> #{new_head}")
  else
    ## Clone a copy of the repository to this location
    system("git clone #{payload['repository']['clone_url']} tmp/#{repo_id} --depth 1")
    log("-> Cloned repository from '#{payload['repository']['clone_url']}' to 'tmp/#{repo_id}'")    
  end
  
  ## find the name of the gemspec for this repository
  files = `cd tmp/#{repo_id} && git ls-tree --name-only master`.match(/(\w+\.gemspec)/)
  if files
    log "-> Gemspec found at '#{files[0]}'"
    gemspec_filename = files[0]
  else
    return log "!! No gemspec found in repository root."
  end
  
  gemspec = File.read("tmp/#{repo_id}/#{gemspec_filename}")
  ## get the version
  version = gemspec.match(/version \= \"(.*)\"/)
  if version
    version = version[1]
    log "-> Version is: #{version}"
  else
    return log "!! No version found in gemspec."
  end
    
  ## build gem
  gem_path = "/Users/adam/projects/gembuilder/gems" ## no trailing slash
  
  ## does the gem exist?
  expected_gem_name = gemspec_filename.gsub(".gemspec", "-#{version}.gem")
  log "-> Checking for gem with name of #{expected_gem_name}"
  unless File.exist?(File.join(gem_path, "gems", expected_gem_name))
    ## make the folders
    system("mkdir -p #{gem_path}/gems")
    system("cd tmp/#{repo_id} && gem build #{gemspec_filename}")
    ## move them into the gem path
    system("mv tmp/#{repo_id}/*.gem #{gem_path}/gems/")
    log "-> Gem Built and moved into #{gem_path}/gems"
    ## make a sync
    system("cd #{gem_path} && gem generate_index")
    log "-> Generated Gem index"
  else
    return log "!! Gem with matching version already exists. Increase the version number?"
  end
  log("** All done")
    
end


#!/usr/bin/env ruby

require 'bundler/setup'
require 'optparse'
require 'json'
require 'yaml'
require 'curb'
require 'cgi'

def config
  YAML.load_file(File.expand_path(__dir__) << '/config.yml')
rescue Errno::ENOENT
  puts 'config.yml not found'
  exit(1)
end

## method to query puppetdb
def query_pdb(host, path)
  proto = host['ssl'] ? 'https://' : 'http://'
  pdbhost = "#{proto}#{host['hostname']}:#{host['port']}".freeze
  cache_filename = "#{pdbhost}#{path}".gsub!('/', '')

  return File.read(cache_filename) if config['mode'] == 'development' && File.exist?(cache_filename)

  c = Curl::Easy.new("#{pdbhost}#{path}") do |curl|
    if host['ssl']
      curl.cacert   = host['cacert'].to_s
      curl.cert     = host['cert'].to_s
      curl.cert_key = host['key'].to_s
    end
  end
  c.perform

  File.open(cache_filename, 'w') { |f| f.write(c.body_str) } if config['mode'] == 'development'

  c.body_str
end

## method that binds everything
def build_inventory
  inventory = {
    'all' => {
      'hosts' => []
    },
    '_meta' => {
      'hostvars' => {}
    }
  }

  nodes = {}
  config['puppetdb_servers'].each do |_index, host_info|
    JSON.parse(query_pdb(host_info, '/pdb/query/v4/facts/fqdn')).each do |host|
      nodes[host['certname']] = {}
      nodes[host['certname']]['fqdn'] = host['value']
    end
    JSON.parse(query_pdb(host_info, '/pdb/query/v4/facts/ipaddress')).each do |host|
      nodes[host['certname']]['ip'] = host['value']
    end
  end

  nodes.each do |_index, node|
    inventory['all']['hosts'].push(node['fqdn'])
    inventory['_meta']['hostvars'][node['fqdn']] = { 'ipaddress' => node['ip'] }
  end

  JSON.generate(inventory)
end

def main
  ## load redis and create connector if used
  if config['use_redis']
    require 'redis'
    redis = Redis.new(
      host: config['redis_host'],
      port: config['redis_port'],
      db: config['redis_index']
    )
    rkey = 'aipdb'.freeze
  end

  # handle options
  options = {}
  OptionParser.new do |opts|
    opts.banner = 'Usage: puppetdb.rb [options]'
    opts.on('--list', 'List Hosts') do
      options[:list] = true
    end
    opts.on('--clear', 'Clear Redis Cache') do
      options[:clear] = true
    end
    opts.on('--build', 'Build Redis Cache') do
      options[:build] = true
    end
  end.parse!

  # handle switches
  if options[:list] || options.empty?
    if config['use_redis']
      redis.set(rkey, build_inventory, ex: config['redis_ttl']) unless redis.get(rkey)
      puts redis.get(rkey)
    else
      puts build_inventory
    end
  end

  REDIS.del(rkey) if options[:clear] && config['use_redis']

  REDIS.set(RKEY, build_inventory, ex: config['redis_ttl']) if options[:build] && config['use_redis']
end

main

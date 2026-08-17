#!/usr/bin/env ruby

require 'bundler/setup'
require 'optparse'
require 'json'
require 'yaml'
require 'net/http'
require 'cgi'

def config
  YAML.load_file(File.expand_path(__dir__) << '/config.yml')
rescue Errno::ENOENT
  puts 'config.yml not found'
  exit(1)
end

## method to query puppetdb
def query_pdb(host, path)
  cache_filename = "#{host['hostname']}:#{host['port']}#{path}".gsub!('/', '')

  return File.read(cache_filename) if config['mode'] == 'development' && File.exist?(cache_filename)

  if host['ssl']
    http_options = {
      use_ssl: true,
      verify_mode: OpenSSL::SSL::VERIFY_PEER,
      keep_alive_timeout: 30,
      cert: OpenSSL::X509::Certificate.new(File.read(host['cert'])),
      key: OpenSSL::PKey::RSA.new(File.read(host['key']))
    }
  else
    http_options = {
      use_ssl: false,
      keep_alive_timeout: 30
    }
  end

  @http = Net::HTTP.start(host['hostname'], host['port'], http_options)
  response = @http.request Net::HTTP::Get.new(path)

  File.open(cache_filename, 'w') { |f| f.write(response.body) } if config['mode'] == 'development'

  response.body
end

## the python interpreter rules from the config, if any
def interpreter_rules
  config['python_interpreters'] || []
end

## the fact names referenced by the interpreter rules, so we only query what we need
def interpreter_facts
  interpreter_rules.flat_map { |rule| (rule['when'] || {}).keys }.uniq
end

## method to check a node's facts against a single rule's conditions
## every condition must match, and a condition can be a single value or a list
def facts_match?(facts, conditions)
  conditions.all? do |fact_name, expected|
    actual = facts[fact_name]
    next false if actual.nil?

    Array(expected).any? { |value| value.to_s.casecmp?(actual.to_s) }
  end
end

## method to find the interpreter for a node, first matching rule wins
def python_interpreter(facts)
  rule = interpreter_rules.find { |r| facts_match?(facts, r['when'] || {}) }
  rule && rule['path']
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
      nodes[host['certname']]['facts'] = {}
    end
    JSON.parse(query_pdb(host_info, '/pdb/query/v4/facts/ipaddress')).each do |host|
      nodes[host['certname']]['ip'] = host['value']
    end
    interpreter_facts.each do |fact_name|
      JSON.parse(query_pdb(host_info, "/pdb/query/v4/facts/#{CGI.escape(fact_name)}")).each do |host|
        next unless nodes.key?(host['certname'])

        nodes[host['certname']]['facts'][fact_name] = host['value']
      end
    end
  end

  nodes.each do |_index, node|
    inventory['all']['hosts'].push(node['fqdn'])
    hostvars = { 'ipaddress' => node['ip'] }
    interpreter = python_interpreter(node['facts'])
    hostvars['ansible_python_interpreter'] = interpreter if interpreter
    inventory['_meta']['hostvars'][node['fqdn']] = hostvars
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

  redis.del(rkey) if options[:clear] && config['use_redis']

  redis.set(rkey, build_inventory, ex: config['redis_ttl']) if options[:build] && config['use_redis']
end

main

#!/usr/bin/env ruby

require 'bundler/setup'
require 'optparse'
require 'json'
require 'yaml'
require 'curb'
require 'cgi'

## load the config
CONFIG = YAML.load_file(File.expand_path(__dir__) <<
                        '/config.yml')

## create the PuppetDB host string
PROTO = CONFIG['ssl'] ? 'https://' : 'http://'
PDBHOST = "#{PROTO}#{CONFIG['hostname']}:#{CONFIG['port']}".freeze

## load redis and create connector if used
if CONFIG['use_redis']
  require 'redis'
  REDIS = Redis.new(host: CONFIG['redis_host'],
                    port: CONFIG['redis_port'],
                    db:   CONFIG['redis_index'])
  RKEY = 'aipdb'.freeze
end

## method to build curl object
def build_curl(url)
  Curl::Easy.new("#{PDBHOST}#{url}") do |curl|
    if CONFIG['ssl']
      curl.cacert = CONFIG['cacert'].to_s
      curl.cert = CONFIG['cert'].to_s
      curl.cert_key = CONFIG['key'].to_s
    end
  end
end

## method to query puppetdb
def query_pdb(url)
  c = build_curl(url)
  c.perform
  c.body_str
end

## method to rearrange facts returned from puppetdb
## so that the key for 'value' is the fact name
## instead of the literal string 'value' and
## deletes the entry for 'name'
def format_facts(array, factname)
  array.each do |h|
    h.store(factname, h.delete('value'))
    h.delete('name')
  end
end

## method to merge arrays of hashes on a common field
def merge_hasharray(array1, array2, commonfield)
  xref = {}
  array2.each { |hash| xref[hash[commonfield]] = hash }
  array1.each do |hash|
    next if xref[hash[commonfield]].empty?
    xref[hash[commonfield]].each_pair do |kk, vv|
      next if commonfield == kk
      hash[kk] = vv
    end
  end
end

## method to make a hacky json inventory for Ansible
def hacky_json(nodes)
  meta = {}
  hosts = []
  nodes.each do |node|
    hosts.push(node['fqdn'])
    meta[node['fqdn']] = { 'ansible_host' => node['ipaddress'] }
  end
  meta = { '_meta' => { 'hostvars' => meta } }
  hosts = { 'all' => { 'hosts' => hosts } }
  JSON.generate(hosts.merge(meta))
end

## method that binds everything
def build_rsp
  fqdn_query = '/pdb/query/v4/facts/fqdn'
  json_hosts_fqdn = JSON.parse(query_pdb(fqdn_query))
  format_facts(json_hosts_fqdn, 'fqdn')
  ip_query = '/pdb/query/v4/facts/ipaddress'
  json_hosts_ip = JSON.parse(query_pdb(ip_query))
  format_facts(json_hosts_ip, 'ipaddress')
  merged_facts = merge_hasharray(json_hosts_fqdn, json_hosts_ip, 'certname')
  hacky_json(merged_facts)
end

## handle options
options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: puppetdb.rb [options]'
  opts.on('--list', 'List Hosts') do
    options[:list] = true
  end
  opts.on('--host', 'List Host Vars') do
    options[:host] = true
  end
  opts.on('--clear', 'Clear Redis Cache') do
    options[:clear] = true
  end
  opts.on('--build', 'Build Redis Cache') do
    options[:build] = true
  end
end.parse!

## handle switches
if options[:list] || options.empty?
  if CONFIG['use_redis']
    REDIS.set(RKEY, build_rsp, ex: CONFIG['redis_ttl']) unless REDIS.get(RKEY)
    puts REDIS.get(RKEY)
  else
    puts build_rsp
  end
end

if options[:host]
  ## individual hostvars aren't currently supported
  puts '{}'
end

if options[:clear]
  REDIS.del(RKEY) if CONFIG['use_redis']
end

if options[:build]
  REDIS.set(RKEY, build_rsp, ex: CONFIG['redis_ttl']) if CONFIG['use_redis']
end

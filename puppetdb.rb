#!/usr/bin/env ruby

require 'bundler/setup'
require 'optparse'
require 'json'
require 'yaml'
require 'curb'
require 'cgi'

## load the config
CONFIG = YAML.load_file(File.expand_path(File.dirname(__FILE__)) <<
                        '/config.yml')

## create the PuppetDB host string
PROTO = CONFIG['ssl'] ? 'https://' : 'http://'
PDBHOST = "#{PROTO}#{CONFIG['hostname']}:#{CONFIG['port']}".freeze

## load redis and create connector if used
require 'redis' if CONFIG['use_redis']
REDIS = Redis.new(host: CONFIG['redis_host'],
                  port: CONFIG['redis_port'],
                  db:   CONFIG['redis_index']) if CONFIG['use_redis']
RKEY = 'aipdb'.freeze if CONFIG['use_redis']

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

## method to get fqdn and ipaddr from node
def get_facts(host)
  fact = "/pdb/query/v4/nodes/#{host}/facts?query=" <<
         CGI.escape('["or", ["=", "name", "ipaddress"],' \
                    ' ["=", "name", "fqdn"]]')
  JSON.parse(query_pdb(fact))
end

## method to pull the certname from the list of nodes
## may be able to consolidate this w/an extract query when fetching the nodes
def get_certname(nodes)
  certnames = []
  nodes.each do |h|
    certnames.push(h['certname'].to_s)
  end
  certnames
end

## build the contents for the meta section of the inventory
## fqdn *should* always be first, and ipaddr second
## we also set the host contents since we're already handling the data
def get_node_info(nodes)
  meta = {}
  hosts = []
  nodes.each do |node|
    facts = []
    get_facts(node).each { |x| facts.push(x) }
    meta[facts[0]['value']] = { 'ansible_host' => facts[1]['value'] }
    hosts.push(facts[0]['value'])
    ## 'hack' to get around doing proper threading/batching
    ## curl gives errors w/out
    sleep(0.1)
  end
  [meta, hosts]
end

## method to make a hacky json inventory for Ansible
def hacky_json(mc, hc)
  meta = { '_meta' => { 'hostvars' => mc } }
  hosts = { 'all' => { 'hosts' => hc } }
  JSON.generate(hosts.merge(meta))
end

## method that binds everything
def build_rsp
  query = '/pdb/query/v4/nodes'
  json_hosts = JSON.parse(query_pdb(query))
  certnames = get_certname(json_hosts)
  meta_contents, hosts_contents = get_node_info(certnames)
  hacky_json(meta_contents, hosts_contents)
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

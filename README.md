# Ansible PuppetDB Dynamic Inventory

This project is a PuppetDB-based dynamic inventory script for use with Ansible.  It allows you to use the "not deactivated" nodes known by PuppetDB as your inventory for plays and playbooks.

## Requirements

  * Ruby (only tested with 2.3.x)
  * 'bundler' Ruby gem
  * Accessable PuppetDB Server
  * Bash (optional - for wrapper script)

## Setup

Clone the repo into the target destination, and from that directory, deploy the required gems.  E.g.:

```
bundle install --path=vendor/
```

## Configuration

The inventory script will look in the same directory as its self for a file named 'config.yml'.  This file accepts the options below in YAML format.

#### `hostname`

The hostname of the PuppetDB server to use.

#### `port`

The port of the PuppetDB server to use.

#### `ssl`

Whether to use SSL for connecting to the PuppetDB server or not.  If enabled, you *must* also specify the cacert, cert, and key options.

#### `cacert`

The CA certificate to use for SSL connections.

#### `cert`

The certificate on the node to use for authentication.

#### `key`

The key file for the certificate used in authentication.

The SSL connection is designed around the idea that the Puppet certificates will be used for authentication.  It may work with other certificate-based authentication, but that is currently untested/unplanned.

There is an [example](example.yml) file included that covers each option, and the input that they accept.

## Usage

Simply point Ansible to the [puppetdb.rb](puppetdb.rb) script as its inventory file:

```
ansible -i puppetdb.rb -m setup your.node
```

Depending on your setup, you may need to use a wrapper to ensure that the included gems are loaded.  There is a [basic wrapper](wrapper.sh) included that can be used.  When using a wrapper, make sure to point to it, instead of the script its self:

```
ansible -i wrapper.sh -m setup your.node
```

### Redis

If you have a lot of active nodes in your PuppetDB instance, this can take a while to return a list.  The inventory can be stored in Redis to cache the output.  The following are valid options to use in the config.yml file.

#### `redis_host`

The hostname/address of the Redis instance to use.

#### `redis_port`

The port number for the Redis instance to use.

#### `redis_index`

The db/index number to use inside the Redis instance.

#### `redis_ttl`

The TTL for the cached inventory inside the Redis instance.

#### Options

If Redis is used, there are a couple additional options the script can use:

  * `puppetdb.rb --build` - This will build the cache, and store it in Redis.  Mainly intended for cron/triggers to keep the inventory updated.
  * `puppetdb.rb --clear` - This will clear the cache manually.  Mainly used for debugging.

## Variables

The script currently only returns one variable, `ansible_host`, which is set to the IP address provided by the Puppet `ipaddress` core fact.  This is mainly to allow connection to hosts that do not have resolvable hostnames.  Other facts are not returned, and are not planned to be implemented.

## License and Copyright

~~~
   Copyright 2016 Nexcess.net

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
~~~


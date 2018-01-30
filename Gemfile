source 'https://rubygems.org'

gem 'curb'
gem 'redis'

## because fedora/rhel
install_if -> { RUBY_PLATFORM =~ /linux/ } do
  gem 'json'
end

group :test do
  gem 'rubocop', require: false
end

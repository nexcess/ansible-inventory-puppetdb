source 'https://rubygems.org'

gem 'redis'

## because fedora/rhel
install_if -> { RUBY_PLATFORM =~ /linux/ } do
  gem 'json', '>= 2.3.0'
end

group :test do
  gem 'rubocop', require: false
end

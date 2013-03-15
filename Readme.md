# omnigollum - omniauth meets gollum

## ACL enabled version by Akretion

We extended Omnigollum to support read/write ACL.
Access rights are set in an auth.md file at level of the directories hierarchy
using the standard markdown embedded Yaml metadata syntax.
The advantage of this is that one can easily grant or revoke permissions just by editing an auth.md wiki page if allowed to do so.
For instance:

`<!--
---
:read:
- group1
- group2
- foo@akretion.com
- bar@akretion.com
- baz@akretion.com
- /(.*)@akretion.com$/
:write:
- foo@akretion.com
- group1
`-->

Notice that you can grant rights individually or as a group. You can also use a regexp syntax like
/(.*)@akretion.com$/ to enable any user which email ends with @akretion.com.

By default user groups are passed as a hardcoded option in your config.ru file.
See the example in the 'Set configuration' section below.
But you may very well override the get_groups method to implement any backend you want.

Finally, permissions are checked from the root of the wiki to the current sub-folder.
This makes it possible to give access to any subfolder of a given subfolder or on the contrary give access only to a given sub-folder.

The following part of the documentation is the one of the original forked project, except for the user groups options example.


## Installation

### Manual

Clone into your ruby library path.

    git clone git://github.com/arr2036/omnigollum.git

## Configuration

Omnigollum executes an OmniAuth::Builder proc/block to figure out which providers you've configured,
then passes it on to omniauth to create the actual omniauth configuration.

To configure both omniauth and omnigollum you should add the following to your config.ru file.

### Load omnigollum library
```ruby
require 'omnigollum'
```

### Load individual provider libraries
```ruby
require 'omniauth/strategies/twitter'
require 'omniauth/strategies/open_id'
```

### Set configuration
```ruby
options = {
  # OmniAuth::Builder block is passed as a proc
  :providers => Proc.new do
    provider :twitter, 'CONSUMER_KEY', 'CONSUMER_SECRET'
    provider :open_id, OpenID::Store::Filesystem.new('/tmp')
  end,
  :dummy_auth => false
  :groups => {:group1 => ['foo@akretion.com', 'bar@akretion.com'], :group2 =>['bar@akretion.com', 'baz@akretion.com']}
}

# :omnigollum options *must* be set before the Omnigollum extension is registered
Precious::App.set(:omnigollum, options)
```

### Register omnigollum extension with sinatra
```ruby
Precious::App.register Omnigollum::Sinatra
```

## Required patches

### mustache

https://github.com/defunkt/mustache

Must be at v0.99.5 (currently unreleased), replace the gem version with 6c4e12d58844d99909df or
the current HEAD.

Feel free to complain loudly that the maintainer should roll a new gem.

### Gollum
You can also (optionally) apply the patches here, to get a neat little auth
status widget in the top right corner of the page https://github.com/arr2036/gollum/commit/32de2cad920ccc6e955b8e19f6e23c2b3b4c8964




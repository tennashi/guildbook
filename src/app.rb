require 'uri'

require 'sinatra/base'
require 'sinatra/config_file'
require 'sinatra/reloader'
require 'sinatra/asset_pipeline'

require 'net/ldap'
require 'net/ldap/dn'
require_relative 'ldap_ext'

require 'haml'
require_relative 'view_helpers'

require 'bootstrap-sass'

module GuildBook
  class App < Sinatra::Base
    set :sessions, true

    register Sinatra::ConfigFile
    config_file '../config/guildbook*.yml'

    set :assets_prefix, %w(src/assets vendor/assets)
    register Sinatra::AssetPipeline

    def absolute_uri(*path)
      url(path.join('/'))
    end

    def get_users(filter = nil)
      ldap_conn do |conn|
        uidFilter = Net::LDAP::Filter.present('uid')
        conn.search(base: settings.ldap_base,
                    filter: filter ? filter & uidFilter : uidFilter,
                    attributes: ['*'])
      end.collect(&:fix_encoding!)
    end

    def get_user(uid)
      ldap_conn do |conn|
        conn.search(base: settings.ldap_base,
                    filter: Net::LDAP::Filter.eq('uid', uid),
                    attributes: ['*']).first or raise Sinatra::NotFound
      end.fix_encoding!
    end

    get '/' do
      users = get_users(~Net::LDAP::Filter.present('shadowExpire'))
      haml :index, locals: {users: users.sort_by {|u| u['uid'].first }}
    end

    get '/:uid' do |uid|
      haml :detail, locals: {user: get_user(uid)}
    end

    get '/:uid/edit' do |uid|
      haml :edit, locals: {user: get_user(uid)}
    end

    post '/:uid/edit' do |uid|
      attrs = %w[
        cn
        sn sn;lang-ja sn;lang-ja;phonetic
        givenName givenName;lang-ja givenName;lang-ja;phonetic
        kmcUnivesityDepartment kmcUniversityStatus kmcUniversityMatric
        alias title kmcGeneration description
        postalCode postalAddress
        mobile homePhone
      ]

      params['cn'] = "#{params['givenName']} #{params['sn']}"

      dn = Net::LDAP::DN.new('uid', params['uid'], settings.ldap_base)
      auth = {method: :simple, username: dn, password: params['password']}
      ldap_conn(auth) do |conn|
        attrs.each do |attr|
          conn.replace_attribute(dn, attr, params[attr])
        end
      end

      redirect absolute_uri(uid)
    end

    private

    def ldap_conn(auth = nil, &block)
      opt = {
        host: settings.ldap_host,
        port: settings.ldap_port,
        encryption: settings.ldap_tls ? :simple_tls : :plaintext,
        auth: auth
      }

      Net::LDAP.open(opt, &block)
    end
  end
end

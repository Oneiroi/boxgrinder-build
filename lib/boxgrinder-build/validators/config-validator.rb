# JBoss, Home of Professional Open Source
# Copyright 2009, Red Hat Middleware LLC, and individual contributors
# by the @authors tag. See the copyright.txt in the distribution for a
# full listing of individual contributors.
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation; either version 2.1 of
# the License, or (at your option) any later version.
#
# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this software; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
# 02110-1301 USA, or see the FSF site: http://www.fsf.org.

require 'boxgrinder-core/validators/errors'

module BoxGrinder
  class ConfigValidator
    def initialize( config, options = {} )
      @config         = config
      @log            = options[:log] || Logger.new(STDOUT)
    end

    def validate
      validate_common
      validate_appliance_dir
    end

    def validate_common
      secure_permissions = "600"

      if File.exists?( @config.config_file )
        conf_file_permissions = sprintf( "%o", File.stat( @config.config_file ).mode )[ 3, 5 ]
        raise ValidationError, "Configuration file (#{@config.config_file}) has wrong permissions (#{conf_file_permissions}), please correct it, run: 'chmod #{secure_permissions} #{@config.config_file}'." unless conf_file_permissions.eql?( secure_permissions )
      end
    end

    def validate_appliance_dir
      raise ValidationError, "Appliances directory '#{@config.dir.appliances}' doesn't exists, please create it: 'mkdir -p #{@config.dir.appliances}'." if !File.exists?(File.dirname( @config.dir.appliances )) && !File.directory?(File.dirname( @config.dir.appliances ))
    end
  end
end

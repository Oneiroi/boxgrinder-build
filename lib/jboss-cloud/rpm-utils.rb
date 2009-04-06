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

require 'rake/tasklib'
require 'net/ssh'
require 'net/sftp'
require 'jboss-cloud/validator/errors'

module JBossCloud
  class RPMUtils < Rake::TaskLib
    
    def initialize( config )
      @config = config
      
      @arches = SUPPORTED_ARCHES + [ "noarch" ]
      @oses   = SUPPORTED_OSES
      
      @connect_data_file = "#{ENV['HOME']}/.jboss-cloud/ssh_data"
      @config_data_file = "#{ENV['HOME']}/.jboss-cloud/config"
      
      if File.exists?( @connect_data_file )
        @connect_data = YAML.load_file( @connect_data_file )
      end
      
      @config_data = {}
      
      # TODO just for now, move this to image-builder, validate, make more globally 
      if File.exists?( @config_data_file )
        @config_data = YAML.load_file( @config_data_file )
        @config_data.gpg_password.gsub!(/\$/, "\\$") unless @config_data.gpg_password.nil?
      end
      
      define
    end
    
    def check_for_password
      if @config_data.gpg_password.nil?
        raise ValidationError, "You have no GPG password specified in JBoss-Cloud config file."
      end
    end
    
    def define     
      task 'rpm:sign:all:srpms' => [ 'rpm:all' ] do
        puts "Signing SRPMs..."
        
        check_for_password
        
        `#{@config.dir.base}/extras/sign-rpms #{@config_data.gpg_password} #{@config.dir_top}/#{APPLIANCE_DEFAULTS['os_name']}/#{APPLIANCE_DEFAULTS['os_version']}/SRPMS/*.src.rpm > /dev/null 2>&1`
        
        unless $?.to_i == 0
          puts "An error occured, some SRPMs may be not signed, check your passphrase"
        else
          puts "All SRPMs successfully signed!"
        end
      end
      
      task 'rpm:sign:all:rpms' => [ 'rpm:all' ] do
        puts "Signing RPMs..."
        
        check_for_password
        
        `#{@config.dir.base}/extras/sign-rpms #{@config_data.gpg_password} #{@config.dir_top}/#{@config.os_path}/RPMS/*/*.rpm > /dev/null 2>&1`
        
        unless $?.to_i == 0
          puts "An error occured, some RPMs may be not signed, check your passphrase"
        else
          puts "All RPMs successfully signed!"
        end
      end
      
      desc "Sign all packages."
      task 'rpm:sign:all' => [ 'rpm:sign:all:rpms', 'rpm:sign:all:srpms' ]
      
      desc "Upload all packages."
      task 'rpm:upload:all' => [ 'rpm:all' ] do
        if (@connect_data.nil?)
          puts "Please specify connection information in '#{@connect_data_file}' file, aborting."
          abort
        end
        
        Net::SSH.start( @connect_data['host'], @connect_data['username']) do |ssh|
          
          puts "Connecting to remote server..."
          ssh.sftp.connect do |sftp|
            
            # create directory structure
            create_directory_if_not_exists( sftp, ssh, @connect_data['remote_rpm_path'] )
            
            begin
              sftp.stat!( @connect_data['remote_rpm_path'] )
            rescue Net::SFTP::StatusException => e
              raise unless e.code == 2
              ssh.exec!( "mkdir -p #{@connect_data['remote_rpm_path']}" )
            end
            
            for os in @oses.keys
              for version in @oses[os]
                for arch in @arches 
                  package_dir = "#{@connect_data['remote_rpm_path']}/#{os}/#{version}/#{arch}"
                  
                  create_directory_if_not_exists( sftp, ssh, package_dir )
                  
                  Dir[ "#{@config.dir.top}/#{os}/#{version}/RPMS/#{arch}/*.rpm" ].each do |rpm_file|             
                    compare_file_and_upload( sftp, rpm_file, "#{package_dir}/#{File.basename( rpm_file )}" )
                  end
                end
                
                puts "Refreshing repository information in #{package_dir}..."
                ssh.exec!( "createrepo #{package_dir}" )
              end
            end
            
            srpms_package_dir = "#{@connect_data['remote_rpm_path']}/SRPMS"
            create_directory_if_not_exists( sftp, ssh, srpms_package_dir )
            
            Dir[ "#{@config.dir_top}/#{APPLIANCE_DEFAULTS['os_name']}/#{APPLIANCE_DEFAULTS['os_version']}/SRPMS/*.src.rpm" ].each do |srpm_file|
              compare_file_and_upload( sftp, srpm_file, "#{srpms_package_dir}/#{File.basename( srpm_file )}" )
            end
            
            puts "Refreshing repository information in #{srpms_package_dir}..."
            ssh.exec!( "createrepo #{srpms_package_dir}" )
          end
          
          puts "Disconnecting from remote server..."
          
        end
      end
    end
    
    def compare_file_and_upload( sftp, file, remote_file )
      puts "File #{File.basename( file )}"
      
      begin
        rstat = sftp.stat!( remote_file )
      rescue Net::SFTP::StatusException => e
        raise unless e.code == 2
        upload_file( sftp, file, remote_file )
        rstat = sftp.stat!( remote_file )
      end
      
      if File.stat(file).mtime > Time.at(rstat.mtime) or File.size(file) != rstat.size
        upload_file( sftp, file, remote_file )
      else
        puts "File exists and is same as local, skipping..."
      end
    end
    
    def upload_file( sftp, local, remote )
      puts "Uploading file #{File.basename( local )} (#{File.size( local ) / 1024}kB)..."
      sftp.upload!(local, remote)
      sftp.setstat(remote, :permissions => 0644)
    end
    
    def create_directory_if_not_exists( sftp, ssh, path )
      begin
        sftp.stat!( path )
      rescue Net::SFTP::StatusException => e
        raise unless e.code == 2
        ssh.exec!( "mkdir -p #{path}" )
      end
    end
    
  end
end
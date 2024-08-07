# frozen_string_literal: true

require 'spec_helper'

describe 'mysql::server::backup' do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:pre_condition) do
        <<-MANIFEST
          class { 'mysql::server': }
        MANIFEST
      end
      let(:facts) do
        facts.merge(root_home: '/root')
      end

      let(:default_params) do
        { 'backupuser' => 'testuser',
          'backuppassword' => 'testpass',
          'backupdir' => '/tmp/mysql-backup',
          'backuprotate' => '25',
          'delete_before_dump' => true,
          'execpath' => '/usr/bin:/usr/sbin:/bin:/sbin:/opt/zimbra/bin',
          'maxallowedpacket' => '1M' }
      end

      context 'standard conditions' do
        let(:params) { default_params }

        # Cannot use that_requires here, doesn't work on classes.
        it {
          expect(subject).to contain_mysql_user('testuser@localhost').with(
            require: 'Class[Mysql::Server::Root_password]',
          )
        }

        it {
          expect(subject).to contain_mysql_grant('testuser@localhost/*.*').with(
            privileges: ['SELECT', 'RELOAD', 'LOCK TABLES', 'SHOW VIEW', 'PROCESS'],
          ).that_requires('Mysql_user[testuser@localhost]')
        }

        context 'with triggers included' do
          let(:params) do
            { include_triggers: true }.merge(default_params)
          end

          it {
            expect(subject).to contain_mysql_grant('testuser@localhost/*.*').with(
              privileges: ['SELECT', 'RELOAD', 'LOCK TABLES', 'SHOW VIEW', 'PROCESS', 'TRIGGER'],
            ).that_requires('Mysql_user[testuser@localhost]')
          }
        end

        it {
          expect(subject).to contain_cron('mysql-backup').with(
            command: '/usr/local/sbin/mysqlbackup.sh',
            ensure: 'present',
          )
        }

        it {
          expect(subject).to contain_file('mysqlbackup.sh').with(
            path: '/usr/local/sbin/mysqlbackup.sh',
            ensure: 'present',
          )
        }

        it {
          expect(subject).to contain_file('/tmp/mysql-backup').with(
            ensure: 'directory',
          )
        }

        it 'has compression by default' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(
            %r{bzcat -zc},
          )
        end

        it 'skips backing up events table by default' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(
            %r{ADDITIONAL_OPTIONS="--ignore-table=mysql.event"},
          )
        end

        it 'does not mention triggers by default because file_per_database is false' do
          expect(subject).to contain_file('mysqlbackup.sh').without_content(
            %r{.*triggers.*},
          )
        end

        it 'does not mention routines by default because file_per_database is false' do
          expect(subject).to contain_file('mysqlbackup.sh').without_content(
            %r{.*routines.*},
          )
        end

        it 'has 25 days of rotation' do
          # MySQL counts from 0
          expect(subject).to contain_file('mysqlbackup.sh').with_content(%r{.*ROTATE=24.*})
        end

        it 'has a standard PATH' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(%r{PATH=/usr/bin:/usr/sbin:/bin:/sbin:/opt/zimbra/bin})
        end
      end

      context 'with delete after dump' do
        let(:custom_params) do
          {
            'delete_before_dump' => false
          }
        end
        let(:params) do
          default_params.merge!(custom_params)
        end

        it { is_expected.to contain_file('mysqlbackup.sh').with_content(%r{touch /tmp/mysqlbackup_success}) }
      end

      context 'with delete after dump and custom success file path' do
        let(:custom_params) do
          {
            'delete_before_dump' => false,
            'backup_success_file_path' => '/opt/mysqlbackup_success'
          }
        end
        let(:params) do
          default_params.merge!(custom_params)
        end

        it { is_expected.to contain_file('mysqlbackup.sh').with_content(%r{touch /opt/mysqlbackup_success}) }
      end

      context 'custom ownership and mode for backupdir' do
        let(:params) do
          { backupdirmode: '0750',
            backupdirowner: 'testuser',
            backupdirgroup: 'testgrp' }.merge(default_params)
        end

        it {
          expect(subject).to contain_file('/tmp/mysql-backup').with(
            ensure: 'directory',
            mode: '0750',
            owner: 'testuser',
            group: 'testgrp',
          )
        }
      end

      context 'with compression disabled' do
        let(:params) do
          { backupcompress: false }.merge(default_params)
        end

        it {
          expect(subject).to contain_file('mysqlbackup.sh').with(
            path: '/usr/local/sbin/mysqlbackup.sh',
            ensure: 'present',
          )
        }

        it 'is able to disable compression' do
          expect(subject).to contain_file('mysqlbackup.sh').without_content(
            %r{.*bzcat -zc.*},
          )
        end
      end

      context 'with mysql.events backedup' do
        let(:params) do
          { ignore_events: false }.merge(default_params)
        end

        it {
          expect(subject).to contain_file('mysqlbackup.sh').with(
            path: '/usr/local/sbin/mysqlbackup.sh',
            ensure: 'present',
          )
        }

        it 'is able to backup events table' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(
            %r{ADDITIONAL_OPTIONS="--events"},
          )
        end
      end

      context 'with database list specified' do
        let(:params) do
          { backupdatabases: ['mysql'] }.merge(default_params)
        end

        it {
          expect(subject).to contain_file('mysqlbackup.sh').with(
            path: '/usr/local/sbin/mysqlbackup.sh',
            ensure: 'present',
          )
        }

        it 'has a backup file for each database' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(
            %r{mysql | bzcat -zc \${DIR}\\\${PREFIX}mysql_`date'},
          )
        end

        it 'skips backup triggers by default' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(
            %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --skip-triggers"},
          )
        end

        it 'skips backing up routines by default' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(
            %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --skip-routines"},
          )
        end

        context 'with include_triggers set to true' do
          let(:params) do
            default_params.merge(backupdatabases: ['mysql'],
                                 include_triggers: true)
          end

          it 'backups triggers when asked' do
            expect(subject).to contain_file('mysqlbackup.sh').with_content(
              %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --triggers"},
            )
          end
        end

        context 'with include_triggers set to false' do
          let(:params) do
            default_params.merge(backupdatabases: ['mysql'],
                                 include_triggers: false)
          end

          it 'skips backing up triggers when asked to skip' do
            expect(subject).to contain_file('mysqlbackup.sh').with_content(
              %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --skip-triggers"},
            )
          end
        end

        context 'with include_routines set to true' do
          let(:params) do
            default_params.merge(backupdatabases: ['mysql'],
                                 include_routines: true)
          end

          it 'backups routines when asked' do
            expect(subject).to contain_file('mysqlbackup.sh').with_content(
              %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --routines"},
            )
          end
        end

        context 'with include_routines set to false' do
          let(:params) do
            default_params.merge(backupdatabases: ['mysql'],
                                 include_triggers: true)
          end

          it 'skips backing up routines when asked to skip' do
            expect(subject).to contain_file('mysqlbackup.sh').with_content(
              %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --skip-routines"},
            )
          end
        end
      end

      context 'with file per database' do
        let(:params) do
          default_params.merge(file_per_database: true)
        end

        it 'loops through backup all databases' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(%r{.*SHOW DATABASES.*})
        end

        context 'with compression disabled' do
          let(:params) do
            default_params.merge(file_per_database: true, backupcompress: false)
          end

          it 'loops through backup all databases without compression #show databases' do
            expect(subject).to contain_file('mysqlbackup.sh').with_content(%r{.*SHOW DATABASES.*})
          end

          it 'loops through backup all databases without compression #bzcat' do
            expect(subject).to contain_file('mysqlbackup.sh').without_content(%r{.*bzcat -zc.*})
          end
        end

        it 'skips backup triggers by default' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(
            %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --skip-triggers"},
          )
        end

        it 'skips backing up routines by default' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(
            %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --skip-routines"},
          )
        end

        context 'with include_triggers set to true' do
          let(:params) do
            default_params.merge(file_per_database: true,
                                 include_triggers: true)
          end

          it 'backups triggers when asked' do
            expect(subject).to contain_file('mysqlbackup.sh').with_content(
              %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --triggers"},
            )
          end
        end

        context 'with include_triggers set to false' do
          let(:params) do
            default_params.merge(file_per_database: true,
                                 include_triggers: false)
          end

          it 'skips backing up triggers when asked to skip' do
            expect(subject).to contain_file('mysqlbackup.sh').with_content(
              %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --skip-triggers"},
            )
          end
        end

        context 'with include_routines set to true' do
          let(:params) do
            default_params.merge(file_per_database: true,
                                 include_routines: true)
          end

          it 'backups routines when asked' do
            expect(subject).to contain_file('mysqlbackup.sh').with_content(
              %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --routines"},
            )
          end
        end

        context 'with include_routines set to false' do
          let(:params) do
            default_params.merge(file_per_database: true,
                                 include_triggers: true)
          end

          it 'skips backing up routines when asked to skip' do
            expect(subject).to contain_file('mysqlbackup.sh').with_content(
              %r{ADDITIONAL_OPTIONS="\$ADDITIONAL_OPTIONS --skip-routines"},
            )
          end
        end
      end

      context 'with postscript' do
        let(:params) do
          default_params.merge(postscript: 'rsync -a /tmp backup01.local-lan:')
        end

        it 'is add postscript' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(
            %r{rsync -a /tmp backup01.local-lan:},
          )
        end
      end

      context 'with postscripts' do
        let(:params) do
          default_params.merge(postscript: [
                                 'rsync -a /tmp backup01.local-lan:',
                                 'rsync -a /tmp backup02.local-lan:',
                               ])
        end

        it 'is add postscript' do
          expect(subject).to contain_file('mysqlbackup.sh').with_content(
            %r{.*rsync -a /tmp backup01.local-lan:\n\nrsync -a /tmp backup02.local-lan:.*},
          )
        end
      end
    end
  end
end

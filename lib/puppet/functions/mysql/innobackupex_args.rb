# frozen_string_literal: true

# @summary
#   This function populates and returns the string of arguments which later gets injected in template. Arguments that return string holds is conditional and decided by the the input given to function.
#
Puppet::Functions.create_function(:'mysql::innobackupex_args') do
  # @param backupuser
  #   The user to use for the backup.
  # @param backupcompress
  #   If the backup should be compressed.
  # @param backuppassword_unsensitive
  #   The password to use for the backup.
  # @param backupdatabases
  #   The databases to backup.
  # @param optional_args
  #   Additional arguments to pass to innobackupex.
  #
  # @return String
  #   Generated on the basis of provided values.
  #
  dispatch :innobackupex_args do
    required_param 'Optional[String]', :backupuser
    required_param 'Boolean', :backupcompress
    required_param 'Optional[Variant[String, Sensitive[String]]]', :backuppassword_unsensitive
    required_param 'Array[String[1]]', :backupdatabases
    required_param 'Array[String[1]]', :optional_args
    return_type 'Variant[String]'
  end

  def innobackupex_args(backupuser, backupcompress, backuppassword_unsensitive, backupdatabases, optional_args)
    innobackupex_args = ''
    innobackupex_args = "--user=\"#{backupuser}\" --password=\"#{backuppassword_unsensitive}\"" if backupuser && backuppassword_unsensitive

    innobackupex_args = "#{innobackupex_args} --compress" if backupcompress

    innobackupex_args = "#{innobackupex_args} --databases=\"#{backupdatabases.join(' ')}\"" if backupdatabases.is_a?(Array) && !backupdatabases.empty?

    if optional_args.is_a?(Array)
      optional_args.each do |arg|
        innobackupex_args = "#{innobackupex_args} #{arg}"
      end
    end
    innobackupex_args
  end
end

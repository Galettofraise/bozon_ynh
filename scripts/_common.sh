#
# Common variables & functions
#

# Package dependencies
PKG_DEPENDENCIES="php5-curl php5-gd"

# Check if directory/file already exists (path in argument)
myynh_check_path () {
	[ -z "$1" ] && ynh_die "No argument supplied"
	[ ! -e "$1" ] || ynh_die "$1 already exists"
}

# Create directory only if not already exists (path in argument)
myynh_create_dir () {
	[ -z "$1" ] && ynh_die "No argument supplied"
	[ -d "$1" ] || sudo mkdir -p "$1"
}

# Check if enough disk space available on backup storage
myynh_check_disk_space () {
	file_to_analyse=$1
	backup_size=$(sudo du --summarize "$1" | cut -f1)
	free_space=$(sudo df --output=avail "/home/yunohost.backup" | sed 1d)
	if [ $free_space -le $backup_size ]
	then
		WARNING echo "Not enough backup disk space for: $1"
		WARNING echo "Space available: $(HUMAN_SIZE $free_space)"
		ynh_die "Space needed: $(HUMAN_SIZE $backup_size)"
	fi
}

# Create a dedicated nginx config
myynh_add_nginx_config () {
	ynh_backup_if_checksum_is_different "$nginx_conf" 1
	sudo cp ../conf/nginx.conf "$nginx_conf"
	# To avoid a break by set -u, use a void substitution ${var:-}. If the variable is not set, it's simply set with an empty variable.
	# Substitute in a nginx config file only if the variable is not empty
	if test -n "${path_url:-}"; then
		ynh_replace_string "__PATH__" "$path_url" "$nginx_conf"
	fi
	if test -n "${final_path:-}"; then
		ynh_replace_string "__FINALPATH__" "$final_path" "$nginx_conf"
	fi
	if test -n "${app:-}"; then
		ynh_replace_string "__NAME__" "$app" "$nginx_conf"
	fi
	if test -n "${filesize:-}"; then
		ynh_replace_string "__FILESIZE__" "$filesize" "$nginx_conf"
	fi
	ynh_store_file_checksum "$nginx_conf"
	sudo systemctl reload nginx
}

# Remove the dedicated nginx config
myynh_remove_nginx_config () {
	ynh_secure_remove "$nginx_conf"
	sudo systemctl reload nginx
}

# Create a dedicated php-fpm config
myynh_add_fpm_config () {
	ynh_backup_if_checksum_is_different "$phpfpm_conf" 1
	sudo cp ../conf/php-fpm.conf "$phpfpm_conf"
	postsize=${filesize%?}.1${filesize: -1}
	ynh_replace_string "__FINALPATH__" "$final_path" "$phpfpm_conf"
	ynh_replace_string "__NAME__" "$app" "$phpfpm_conf"
	ynh_replace_string "__FILESIZE__" "$filesize" "$phpfpm_conf"
	ynh_replace_string "__POSTSIZE__" "$postsize" "$phpfpm_conf"
	sudo chown root: "$phpfpm_conf"
	ynh_store_file_checksum "$phpfpm_conf"
	sudo systemctl reload php5-fpm
}

# Remove the dedicated php-fpm config
myynh_remove_fpm_config () {
	ynh_secure_remove "$phpfpm_conf"
	sudo systemctl restart php5-fpm
}

#=================================================
# FUTURE YUNOHOST HELPERS - TO BE REMOVED LATER
#=================================================
# Restore a previous backup if the upgrade process failed
ynh_backup_after_failed_upgrade () {
	echo "Upgrade failed." >&2
	app_bck=${app//_/-}	# Replace all '_' by '-'
	# Check if a existing backup can be found before remove and restore the application.
	if sudo yunohost backup list | grep -q $app_bck-upg$backup_number; then
		# Remove the application then restore it
		sudo yunohost app remove $app
		# Restore the backup if the upgrade failed
		sudo yunohost backup restore --ignore-system $app_bck-upg$backup_number --apps $app --force
		ynh_die "The app was restored to the way it was before the failed upgrade."
	fi
}

# Make a backup in case of failed upgrade
ynh_backup_before_upgrade () {
	backup_number=1
	old_backup_number=2
	app_bck=${app//_/-}	# Replace all '_' by '-'
	# Check if a backup already exist with the prefix 1.
	if sudo yunohost backup list | grep -q $app_bck-upg1; then
		# Prefix become 2 to preserve the previous backup
		backup_number=2
		old_backup_number=1
	fi
	# Create another backup
	sudo yunohost backup create --ignore-system --apps $app --name $app_bck-upg$backup_number
	if [ "$?" -eq 0 ]; then
		# If the backup succedded, remove the previous backup
		if sudo yunohost backup list | grep -q $app_bck-upg$old_backup_number; then
			# Remove the previous backup only if it exists
			sudo yunohost backup delete $app_bck-upg$old_backup_number > /dev/null
		fi
	else
		ynh_die "Backup failed, the upgrade process was aborted."
	fi
}
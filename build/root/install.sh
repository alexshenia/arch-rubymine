#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl --connect-timeout 5 --max-time 600 --retry 5 --retry-delay 0 --retry-max-time 60 -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
mv /tmp/scripts-master/shell/arch/docker/*.sh /usr/local/bin/

# pacman packages
####

# call pacman db and package updater script
source upd.sh

# define pacman packages
pacman_packages="git tk  gcc"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aur packages
####

# define aur packages
aur_packages="websockify rubymine rvm"

# call aur install script (arch user repo)
source aur.sh

# config rubymine
####

# set rubymine path selector, this changes the path used by rubymine to check for a custom idea.properties file
# the path is constructed from /home/nobody/.<idea.paths.selector value>/config/ so the idea.properties file then needs
# to be located in /home/nobody/.config/rubymine/idea.properties, note double backslash to escape end backslash
sed -i -e 's~-Didea.paths.selector=.*~-Didea.paths.selector=config/rubymine \\~g' /usr/share/rubymine/bin/rubymine.sh

# set rubymine paths for config, plugins, system and log, note the location of the idea.properties
# file is constructed from the idea.paths.selector value, as shown above.
mkdir -p /home/nobody/.config/rubymine/config
echo "idea.config.path=/config/rubymine/config" > /home/nobody/.config/rubymine/config/idea.properties
echo "idea.plugins.path=/config/rubymine/config/plugins" >> /home/nobody/.config/rubymine/config/idea.properties
echo "idea.system.path=/config/rubymine/system" >> /home/nobody/.config/rubymine/config/idea.properties
echo "idea.log.path=/config/rubymine/system/log" >> /home/nobody/.config/rubymine/config/idea.properties

cat <<'EOF' > /tmp/startcmd_heredoc
# check if recent projects directory config file exists, if it doesnt we assume
# rubymine hasn't been run yet and thus set default location for future projects to
# external volume mapping.
if [ ! -f /config/rubymine/config/options/recentProjectDirectories.xml ]; then
	mkdir -p /config/rubymine/config/options
	cp /home/nobody/recentProjectDirectories.xml /config/rubymine/config/options/recentProjectDirectories.xml
fi

# run rubymine
/usr/bin/jetbrains-rubymine
EOF

# replace startcmd placeholder string with contents of file (here doc)
sed -i '/# STARTCMD_PLACEHOLDER/{
    s/# STARTCMD_PLACEHOLDER//g
    r /tmp/startcmd_heredoc
}' /home/nobody/start.sh
rm /tmp/startcmd_heredoc

# config novnc
###

# overwrite novnc 16x16 icon with application specific 16x16 icon (used by bookmarks and favorites)
cp /home/nobody/novnc-16x16.png /usr/share/webapps/novnc/app/images/icons/

# config openbox
####

cat <<'EOF' > /tmp/menu_heredoc
    <item label="RuBymine">
    <action name="Execute">
      <command>rubymine</command>
      <startupnotify>
        <enabled>yes</enabled>
      </startupnotify>
    </action>
    </item>
EOF

# replace menu placeholder string with contents of file (here doc)
sed -i '/<!-- APPLICATIONS_PLACEHOLDER -->/{
    s/<!-- APPLICATIONS_PLACEHOLDER -->//g
    r /tmp/menu_heredoc
}' /home/nobody/.config/openbox/menu.xml
rm /tmp/menu_heredoc

# container perms
####

# define comma separated list of paths 
install_paths="/tmp,/usr/share/themes,/home/nobody,/usr/share/webapps/novnc,/usr/share/rubymine,/usr/share/applications,/etc/xdg"

# split comma separated string into list for install paths
IFS=',' read -ra install_paths_list <<< "${install_paths}"

# process install paths in the list
for i in "${install_paths_list[@]}"; do

	# confirm path(s) exist, if not then exit
	if [[ ! -d "${i}" ]]; then
		echo "[crit] Path '${i}' does not exist, exiting build process..." ; exit 1
	fi

done

# convert comma separated string of install paths to space separated, required for chmod/chown processing
install_paths=$(echo "${install_paths}" | tr ',' ' ')

# set permissions for container during build - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
chmod -R 775 ${install_paths}

# create file with contents of here doc, note EOF is NOT quoted to allow us to expand current variable 'install_paths'
# we use escaping to prevent variable expansion for PUID and PGID, as we want these expanded at runtime of init.sh
cat <<EOF > /tmp/permissions_heredoc

# get previous puid/pgid (if first run then will be empty string)
previous_puid=\$(cat "/root/puid" 2>/dev/null || true)
previous_pgid=\$(cat "/root/pgid" 2>/dev/null || true)

# if first run (no puid or pgid files in /tmp) or the PUID or PGID env vars are different 
# from the previous run then re-apply chown with current PUID and PGID values.
if [[ ! -f "/root/puid" || ! -f "/root/pgid" || "\${previous_puid}" != "\${PUID}" || "\${previous_pgid}" != "\${PGID}" ]]; then

	# set permissions inside container - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
	chown -R "\${PUID}":"\${PGID}" ${install_paths}

fi

# write out current PUID and PGID to files in /root (used to compare on next run)
echo "\${PUID}" > /root/puid
echo "\${PGID}" > /root/pgid

EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
    s/# PERMISSIONS_PLACEHOLDER//g
    r /tmp/permissions_heredoc
}' /usr/local/bin/init.sh
rm /tmp/permissions_heredoc

# env vars
####

# cleanup
cleanup.sh

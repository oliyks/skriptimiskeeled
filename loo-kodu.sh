#!/bin/bash 
#Autor  Tarmo Oja
#
#Skript mis teeb argumendina antud nimelise apache2 virtualserveri

#break when non-zero return is encountered
set -e

#set some defaults
#which direcory is the template for the new VS
template_dir=/var/www/html
#where we put VS direcories
virtual_root=/var/www
#new hostname, read from command argument
hostname=$1
#what are we adding to index.html
custom_string=" - Site for $hostname"


# Lets tell user if he needs read output for errors
error_exit() {
  echo -e "\nThere was a bad error! Check output\n"
  exit 1
}

#catch exit code, if 0 -> all good
trap '[ "$?" -eq 0 ] && echo -e "\nSucess!\n" || error_exit ' EXIT


# do we have hostname as command argument
check_argument() {
   if [[ "$hostname" == "" ]] 
     then
       echo "Please call script as $0 <hostname>"
       exit 1
     else
       echo "Trying to create virtualserver for hostname: $hostname"
     fi
}

# do we have root access
are_we_root() {
   echo -n "Checking if effective user is root: "
   if [[ `id -u` != 0 ]]
     then
       echo "You are not root, aborting"
       echo "start with sudo $0"
       exit 1
     else
       echo "root, continuing"
   fi
}

#check apache2 installation status, if not installed - call install
#note: breaking on non-zero return is disabled 
check_apache_installed() {

   echo -n "Checking if webserver has been installed: "
   set +e
   dpkg -l  apache2 | grep -q '^ii'
   ret=$?
   set -e

   if [[ "$ret" != "0" ]] 
     then
       echo "no apache, installing"
       install_apache
     else
       echo "apache installed"
   fi
}

#install apache
install_apache() {
    echo "Installing apache"
    apt update -y
    apt install -y apache2
}

#check if hostname is already existing with ping
#if no success add hostname <-> 127.0.1.1 to /etc/hosts
modify_etc_hosts() {

   echo -n "Is host \"$hostname\" resolvable? "
   set +e
   output=`ping -q -c 1 -W 1 $hostname 2>/dev/null`
   ret=$?
   set -e
   if [[ "$ret" == 0 ]]
     then
       echo "Yes, host "$hostname" responds on IP: `echo $output | awk '{print $3}' | tr -d '()'`"
     else
       echo "No, adding $hostname -> 127.0.1.1 to /etc/hosts "
       grep -q '127.0.1.1' /etc/hosts && 
	    sed -i "s/\(127\.0\.1\.1.*\)/\1 $hostname/" /etc/hosts || echo "127.0.1.1  $hostname" >> /etc/hosts
 
     fi
}

#check if VS directory exists, if not copy from template and add hostname to it
make_virtualhost_directory() {
   echo -n "Create VS root dir: "
   if [[ -d /var/www/$hostname ]]
     then
       echo "Virtual server root seems to be exist, skipping"
     else
      echo "Copying from template"
      if [[ ! -d $virtual_root ]]
        then
          echo "virtual server root missing, creating one"
          install --mode 755 -d $virtual_root
        fi
      cp -r $template_dir $virtual_root/$hostname
      sed -i "s/\(Apache2 Ubuntu Default Page\)/\1 $custom_string/g" $virtual_root/$hostname/index.html
   fi

}

#create VS apache2 config, enable site and restart apache
configure_virtualserver() {

    if [[ -f /etc/apache2/sites-available/${hostname}.conf ]]
      then
        echo "virtual server configfile exists, skiping"
      else
        echo "configuring virtual server"
     cat > /etc/apache2/sites-available/${hostname}.conf <<EOF

<VirtualHost *:80>
        ServerName ${hostname}
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/${hostname}
        ErrorLog ${APACHE_LOG_DIR}/${hostname}.error.log
        CustomLog ${APACHE_LOG_DIR}/${hostname}.access.log combined
</VirtualHost>

# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
EOF

     fi
     if [[ ! -L /etc/apache2/sites-enabled/${hostname}.conf ]]
     then 
        echo "There is no symlink, creating"
	a2ensite $hostname
     else
        echo "There is symlink"
     fi
     echo "restarting apache"
     service apache2 restart
}

#Try to connect to new VS and find if the custom string is there
check_vs() {

    if [[ ! -x `which nc` ]]
      then
        echo "NetCat is not executable, skiping site test. Hoping for the best!"
        return
    fi
    
    echo "Checking if we can get something from VS"
    set +e
    response=`echo -e "GET / HTTP/1.1\nHost: $hostname\n\n" | nc -w 1 -vv $hostname 80`
    ret=$?
    set -e
    if [[ "$ret" != "0" ]]
      then
        echo "cannot connect to $hostname"
        exit 1
      else
        echo $response | grep -q "$custom_string" && echo "Working fine" || exit 1
    fi

}

#here we call procedures - workflow is defined here
check_argument
are_we_root
check_apache_installed
modify_etc_hosts
make_virtualhost_directory
configure_virtualserver
check_vs

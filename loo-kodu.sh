#!/bin/bash 
#Autor  Tarmo Oja
#
#Skript mis teeb argumendina antud nimelise nginx virtualserveri


set -e

template_dir=/usr/share/nginx/html
virtual_root=/var/www
hostname=$1
custom_string=" - Site for $hostname"

error_exit() {
  echo -e "\nThere was a bad error! Check output\n"
  exit 1
}

trap '[ "$?" -eq 0 ] && echo -e "\nSucess!\n" || error_exit ' EXIT

check_argument() {

   if [[ "$hostname" == "" ]] 
     then
       echo "Please call script as $0 <hostname>"
       exit 1
     else
       echo "Trying to create virtualserver for hostname: $hostname"
     fi
}

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


check_nginx_installed() {

   echo -n "Checking if Nginx has been installed: "
   set +e
   dpkg -l  nginx* | grep -E "nginx-full|nginx-extras|nginx-light" | grep -q '^ii'
   ret=$?
   set -e

   if [[ "$ret" != "0" ]] 
     then
       echo "no nginx, installing"
       install_nginx
     else
       echo "nginx installed"
   fi
}

install_nginx() {
    echo "Installing nginx-light"
    apt update -y
    apt install -y nginx-light
}

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
      sed -i "s/\(Welcome to nginx!\)/\1 $custom_string/g" $virtual_root/$hostname/index.html
   fi

}

configure_virtualserver() {

    if [[ -f /etc/nginx/sites-available/$hostname ]]
      then
        echo "virtual server configfile exists, skiping"
      else
        echo "configuring virtual server"
     cat > /etc/nginx/sites-available/$hostname <<EOF

     server {
            listen 80;
            listen [::]:80;

            server_name $hostname;

            root /var/www/$hostname;
            index index.html;

            location / {
                    try_files \$uri \$uri/ =404;
            }
     }
EOF

     fi
     if [[ ! -L /etc/nginx/sites-enabled/$hostname ]]
     then 
        echo "There is no symlink, creating"
        ln -sf /etc/nginx/sites-available/$hostname /etc/nginx/sites-enabled/$hostname
     else
        echo "There is symlink"
     fi
     echo "restarting Nginx"
     service nginx restart
}

check_vs() {

    if [[ ! -x `which nc` ]]
      then
        echo "NetCat is not executable, skiping site test. Hoping for the best!"
        return
    fi
    
    echo "Checking if we can get something from VS"
    set +e
    response=`echo -e "GET / HTTP/1.1\nHost: $hostname\n\n" | nc -vv $hostname 80`
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

check_argument
are_we_root
check_nginx_installed
modify_etc_hosts 
make_virtualhost_directory
configure_virtualserver
check_vs

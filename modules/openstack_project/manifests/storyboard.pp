# == Class: openstack_project::storyboard
#
class openstack_project::storyboard(
  $mysql_host = '',
  $mysql_password = '',
  $mysql_user = '',
  $rabbitmq_user = 'storyboard',
  $rabbitmq_password,
  $superusers =
    'puppet:///modules/openstack_project/storyboard/superusers.yaml',
  $ssl_cert = undef,
  $ssl_cert_file_contents = undef,
  $ssl_key = undef,
  $ssl_key_file_contents = undef,
  $ssl_chain_file_contents = undef,
  $openid_url = 'https://login.ubuntu.com/+openid',
  $project_config_repo = '',
  $hostname = $::fqdn,
  $valid_oauth_clients = [$::fqdn],
  $cors_allowed_origins = ["https://${::fqdn}"],
  $sender_email_address = undef,
  $default_url = undef,
) {

  class { 'project_config':
    url  => $project_config_repo,
  }

  class { 'openstack_project::server': }


  class { '::storyboard::mysql':
    mysql_database         => 'storyboard',
    mysql_user             => $mysql_user,
    mysql_user_password    => $mysql_password,
  }

  mysql_backup::backup { 'storyboard':
    require => Class['::storyboard::mysql'],
  }

  class { '::storyboard::cert':
    ssl_cert_content => $ssl_cert_file_contents,
    ssl_cert         => $ssl_cert,
    ssl_key_content  => $ssl_key_file_contents,
    ssl_key          => $ssl_key,
    ssl_ca_content   => $ssl_chain_file_contents,
  }

  class { '::storyboard::application':
    hostname               => $hostname,
    cors_allowed_origins   => $cors_allowed_origins,
    valid_oauth_clients    => $valid_oauth_clients,
    cors_max_age           => 3600,
    openid_url             => $openid_url,
    mysql_host             => $mysql_host,
    mysql_database         => 'storyboard',
    mysql_user             => $mysql_user,
    mysql_user_password    => $mysql_password,
    rabbitmq_host          => 'localhost',
    rabbitmq_port          => 5672,
    rabbitmq_vhost         => '/',
    rabbitmq_user          => $rabbitmq_user,
    rabbitmq_user_password => $rabbitmq_password,
    sender_email_address   => $sender_email_address,
    default_url            => $default_url,
  }

  class { '::storyboard::rabbit':
    rabbitmq_user          => $rabbitmq_user,
    rabbitmq_user_password => $rabbitmq_password,
  }

  class { '::storyboard::workers':
    worker_count => 5,
  }

  # Load the projects into the database.
  class { '::storyboard::load_projects':
    source  => $::project_config::jeepyb_project_file,
    require => $::project_config::config_dir,
  }

  # Load the superusers into the database
  class { '::storyboard::load_superusers':
    source => $superusers,
  }

  include bup
  bup::site { 'ord.rax':
    backup_user   => 'bup-storyboard',
    backup_server => 'backup01.ord.rax.ci.openstack.org',
  }
}

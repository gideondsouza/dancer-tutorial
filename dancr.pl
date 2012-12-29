#!/usr/bin/perl

use Dancer;
use DBI;
use File::Spec;
use File::Slurp;
use Template;
#we'll use this to send requests to github for authentication
use LWP::UserAgent;
#we'll use this to parse json responses from github
use JSON::Parse 'json_to_perl';

 
set 'database'     => File::Spec->catfile(File::Spec->tmpdir(), 'dancr.db');
set 'session'      => 'Simple';
set 'template'     => 'template_toolkit';
set 'logger'       => 'console';
set 'log'          => 'debug';
set 'show_errors'  => 1;
set 'startup_info' => 1;
set 'warnings'     => 1;
set 'username'     => 'admin';
set 'password'     => 'password';
set 'layout'       => 'main';
 
my $flash;

my $client_id = "YOUR CLIENT ID HERE";
my $client_secret = "YOUR SECRET ID HERE";

#this is a utility method that will convert a query string into a hash
sub parse_query_str {
	my $str = shift;
	my %in = ();
	if (length ($str) > 0){
	      my $buffer = $str;
	      my @pairs = split(/&/, $buffer);
	      foreach my $pair (@pairs){
	           my ($name, $value) = split(/=/, $pair);
	           $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
	           $in{$name} = $value; 
	      }
	 }
	return %in;
}

sub set_flash {
       my $message = shift;
 
       $flash = $message;
}
 
sub get_flash {
 
       my $msg = $flash;
       $flash = "";
 
       return $msg;
}
 
sub connect_db {
       my $dbh = DBI->connect("dbi:SQLite:dbname=".setting('database')) or
               die $DBI::errstr;
 
       return $dbh;
}
 
sub init_db {
       my $db = connect_db();
       my $schema = read_file('./schema.sql');
       $db->do($schema) or die $db->errstr;
}
 
hook before_template => sub {
       my $tokens = shift;
        
       $tokens->{'css_url'} = request->base . 'css/style.css';
       $tokens->{'login_url'} = uri_for('/login');
       $tokens->{'logout_url'} = uri_for('/logout');
};
get '/auth/github/callback' => sub {
	my $code                   = params->{'code'};
	my $browser                = LWP::UserAgent->new;
	my $resp                   = $browser->post('https://github.com/login/oauth/access_token',
		[
 			client_id                  => $client_id,
 			client_secret              => $client_secret, 
 			code                       => $code,
 			state                      => 'x12'
		]);
	die "error while fetching: ", $resp->status_line
	    unless $resp->is_success;
	my %querystr = parse_query_str($resp->decoded_content);
	my $acc = $querystr{access_token};
	
	my $jresp  = $browser->get("https://api.github.com/user?access_token=$acc");
	my $json = json_to_perl($jresp->decoded_content);
	session 'username' => $json->{login};
	session 'avatar' => $json->{avatar_url};
	session 'logged_in' => true;
	redirect "/";
};

get '/' => sub {
       my $db = connect_db();
       my $sql = 'select id, title, text from entries order by id desc';
       my $sth = $db->prepare($sql) or die $db->errstr;
       $sth->execute or die $sth->errstr;
       template 'show_entries.tt', {
               'msg' => get_flash(),
               'add_entry_url' => uri_for('/add'),
               'entries' => $sth->fetchall_hashref('id'),
       };
};
 
post '/add' => sub {
       if ( not session('logged_in') ) {
               send_error("Not logged in", 401);
       }
 
       my $db = connect_db();
       my $sql = 'insert into entries (title, text) values (?, ?)';
       my $sth = $db->prepare($sql) or die $db->errstr;
       $sth->execute(params->{'title'}, params->{'text'}) or die $sth->errstr;
 
       set_flash('New entry posted!');
       redirect '/';
};

get '/login' => sub {
	redirect "https://github.com/login/oauth/authorize?&client_id=$client_id&state=x12";
};

 
get '/logout' => sub {
       session->destroy;
       set_flash('You are logged out.');
       redirect '/';
};
 
init_db();
start;


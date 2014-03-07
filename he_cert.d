#!/usr/bin/env rdmd

import std.stdio;
import std.process;
import std.net.curl;
import arsd.dom;
import std.string;
import std.uri;
import std.algorithm;

class Submitter
{
  private {
    HTTP he_http;

    struct job_info {
      bool done;
      string cmdline;
    }

    job_info[string] jobs;

    string hostname;
    string ip;

    string username;
    string password;

    string response_html;

    struct ProcessOutput { int status; string output; }
    ProcessOutput job_output;

    auto submit_url = "https://ipv6.he.net/certification/daily.php?test=%s";
    auto submit_params = "input=%s&submit=Submit";
    auto get_host_url = "http://sixy.ch/ajax/moreRecent";
    auto get_host_params = "offset=%s&count=1";
    auto login_url = "https://ipv6.he.net/certification/login.php";
    auto login_params = "f_user=%s&f_pass=%s&Login=Login";

    auto selector_error = ".errorMessageBox";
    auto selector_info = ".infoMessageBox";
    auto selector_logged_in = ".menu";

    auto path_cookies = "/tmp/.he.cookie";
  }

  this( string user, string pass )
  {
    he_http = HTTP();
    he_http.setCookieJar( path_cookies );

    jobs = [
	    "traceroute" : job_info( false, "traceroute -6" ),
	    "aaaa"       : job_info( false, "dig AAAA" ),
	    "ptr"        : job_info( false, "dig -x" ),
	    "ping"       : job_info( false, "ping6 -n -c3" ),
	    "whois"      : job_info( false, "whois" )
    ];

    username = user;
    password = pass;
  }

  private void get_host()
  {
    static ubyte offset = 0;
    writeln( "Getting new host… " );

    auto document = new Document();

    auto page = cast(string) post( get_host_url, format( get_host_params, offset ) );
    document.parseGarbage( page );

    auto links = document.getElementsByTagName( "a" );

    hostname = links[0].innerText();
    ip = links[1].innerText();

    ++offset;

    writefln( "got host %s with IP %s\n", hostname, ip );
  }

  private bool update_job_status( string cmd_id )
  {
    bool submit_result = false;

    auto document = new Document();
    document.parseGarbage( response_html );

    auto info = document.querySelector( selector_info );
    auto error = document.querySelector( selector_error );

    if ( info ) {
      if ( canFind( info.innerText(), "Pass" ) ) {
	jobs[cmd_id].done = true;
	submit_result = true;
	writeln( "\tSUCCESS" );
      } else
	  writeln( "Submitting info: "~info.innerText() );
    } else if ( error ) {
      if ( canFind( error.innerText(), "last 24 hours" ) ) {
	jobs[cmd_id].done = true;
	submit_result = true;
      }
      writeln( "\tERROR: "~error.innerText() );
    }

    return submit_result;
  }

  private void submit( string cmd_id )
  {
    writeln( "Submitting "~cmd_id~"… " );

    response_html = cast(string) post( format( submit_url, cmd_id ),
		    format(submit_params, job_output.output), he_http );
  }

  private bool login()
  {
    writeln( "Logging in he.net… " );

    auto res = cast(string) post( login_url, 
		    encode( format( login_params, username, password ) ),
		    he_http );

    auto doc = new Document();
    doc.parseGarbage( res );

    if( doc.querySelector( selector_logged_in ) ) {
      writeln( "\tSUCCESS" );
      he_http.flushCookieJar();
      return true;
    } else {
      writeln( "\tERROR: "~doc.querySelector( selector_error ).innerText() );
      he_http.clearAllCookies();
    }

    return false;
  }

  private void invoke( string cmd_id )
  {
    writeln( "Invoking "~cmd_id~"… " );

    job_output = cast(ProcessOutput) executeShell( jobs[cmd_id].cmdline~" "~( cmd_id == "aaaa" ? hostname : ip ) );

    if ( job_output.status == 0 ) {
      writeln( "\tSUCCESS" );
    } else {
      writeln( "\tERROR" );
      writeln( job_output.output );
    }
  }

  void perform()
  {
    if( ! login() )
      return;

    auto num_of_done = 0;

    while ( num_of_done < jobs.length ) {
      num_of_done = 0;
      get_host();
      foreach( string cmd_id, job_info job; jobs ) {
	if( ! job.done ) {
	  invoke( cmd_id );
	  submit( cmd_id );

	  if ( update_job_status( cmd_id ) )
	    ++num_of_done;
	} else 
	  ++num_of_done;
      }
    }

    writeln( "\nJob's done!" );
  }
}

void main()
{
  auto sub = new Submitter( "user", "pass" );
  sub.perform();
}

package DBIx::Migration;

use Moose;

use DBI;
use File::Slurp;
use File::Spec;
use Try::Tiny;
use File::Temp qw/tempfile/;

our $VERSION = '0.09';

has 'debug' => (
    is  => 'ro',
    isa => 'Any',
);

has 'dir' => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

has 'dsn' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'password' => (
    is       => 'ro',
    isa      => 'Str',
    required => 0,
);

has 'username' => (
    is       => 'ro',
    isa      => 'Str',
    required => 0,
);

=head1 VERY IMPORTANT NOTE

 schema_branch is a concept to let Migration package work on several branch AND main branch of schema changes.
 In some situations like that we want to maintain several DB and not all of them need the same set of changes,
 those INDEPENDENT changes can go to a branch.

 Like when we have a report DB and that DB need many specific indices and extra defined functions to work we can create "report" schema branch for that reason.

 Branch directory lives is a sub-dir of main directory.

 branch changes should be applied after main changes.

 branch depends on main schemas but NO MAIN SCHEMA CHANGE-SET should depend on any branch schema.

=cut

has 'tablename_extension' => (
    is      => 'ro',
    isa     => 'Str',
    default => '',
);

has 'schema_branch' => (
    is      => 'ro',
    isa     => 'Str',
    default => '',
);

has '_tablename' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'dbix_migration',
);

sub BUILD {
    my $self = shift;

    if ($self->schema_branch) {
        $self->_tablename($self->_tablename . '_' . $self->schema_branch);
        $self->dir($self->dir . $self->schema_branch . '/');
    } elsif ($self->tablename_extension) {
        $self->_tablename($self->_tablename . '_' . $self->tablename_extension);
    }
    return;
}

=head1 VERY IMPORTANT NOTE

	This package is actually DBIx::Migration package from cpan.

	I have contacted the maintainer of the package and I will try to become maintainer of this package if there was no answer.

	As soon as the bug is fixed in the main package we must get rid of this local package and use the cpan module instead.

	BUG: The bug was because of split/;/. In the main package split based on ";" breaks the file into parts that are not valid for postgres functions.

	ORIGINAL version: "0.05"

=head1 NAME

DBIx::Migration - Seamless DB schema up- and downgrades

=head1 SYNOPSIS

    #Use sampple with a "report" schema branch
    my $m = DBIx::Migration->new({
        'dsn' => 'dbi:Pg:dbname='
        . $database_connection->{'database'}
        . ';host='
        . $database_connection->{'host'}
        . ';port='
        . $database_connection->{'port'},
        'dir'      => $database_connection->{'versions_dir'},
        'username' => $database_connection->{'username'},
        'password' => $database_connection->{'password'},
        'schema_branch' => 'report',
    });

    # migrate.pl
    my $m = DBIx::Migration->new(
        {
            dsn => 'dbi:SQLite:/Users/sri/myapp/db/sqlite/myapp.db',
            dir => '/Users/sri/myapp/db/sqlite'
        }
    );

    my $version = $m->version;   # Get current version from database
    $m->migrate(2);              # Migrate database to version 2

    # /Users/sri/myapp/db/sqlite/schema_1_up.sql
    CREATE TABLE foo (
        id INTEGER PRIMARY KEY,
        bar TEXT
    );

    # /Users/sri/myapp/db/sqlite/schema_1_down.sql
    DROP TABLE foo;

    # /Users/sri/myapp/db/sqlite/schema_2_up.sql
    CREATE TABLE bar (
        id INTEGER PRIMARY KEY,
        baz TEXT
    );

    # /Users/sri/myapp/db/sqlite/schema_2_down.sql
    DROP TABLE bar;

=head1 DESCRIPTION

Seamless DB schema up- and downgrades.

=head1 METHODS

=over 4

=item $self->debug($debug)

Enable/Disable debug messages.

=item $self->dir($dir)

Get/Set directory.

=item $self->dsn($dsn)

Get/Set dsn.

=item $self->migrate($version)

Migrate database to version.

=cut

sub migrate {
    my ($self, $wanted) = @_;
    $self->_connect;
    $wanted = $self->_newest unless defined $wanted;
    my $version = $self->_version;
    if (defined $version && ($wanted eq $version)) {
        print "Database is already at version $wanted\n" if $self->debug;
        return 1;
    }

    unless (defined $version) {
        $self->_create_migration_table;
        $version = 0;
    }

    # Up- or downgrade
    my @need;
    my $type = 'down';
    if ($wanted > $version) {
        $type = 'up';
        $version += 1;
        @need = $version .. $wanted;
    } else {
        $wanted += 1;
        @need = reverse($wanted .. $version);
    }

    my $files = $self->_files($type, \@need);
    if (defined $files) {
        for my $file (@$files) {
            my $name = $file->{name};
            my $ver  = $file->{version};
            print qq/Processing "$name"\n/ if $self->debug;
            next unless $file;

            if ($self->{_dbh}->{Driver}->{Name} eq 'Pg') {
                $self->psql($name);    # dies on error
            } else {
                my $text = read_file($name);

                my $sql = $text;
                next unless $sql =~ /\w/;
                print "$sql\n" if $self->debug;
                $self->{_dbh}->do($sql);
                if ($self->{_dbh}->err) {
                    die "Database error: " . $self->{_dbh}->errstr;
                }
            }

            $ver -= 1 if (($ver > 0) && ($type eq 'down'));
            $self->_update_migration_table($ver);
        }
    } else {
        my $newver = $self->_version;
        print "MIGRATION DID NOT OCCUR\n";
        print "Database is at version [$newver], did not migrate to [$wanted]\n";
        print "No files, bad files, or no migration versions.\n";
        return 0;
    }
    $self->_disconnect;
    return 1;
}

=item $self->password

Get/Set database password.

=item $self->username($username)

Get/Set database username.

=item $self->version

Get migration version from database.

=cut

sub version {
    my $self = shift;
    $self->_connect;
    my $version = $self->_version;
    $self->_disconnect;
    return $version;
}

sub _connect {
    my $self = shift;
    $self->{_dbh} = DBI->connect(
        $self->dsn,
        $self->username,
        $self->password,
        {
            RaiseError => 0,
            PrintError => 0,
            AutoCommit => 1
        }) or die "Couldn't connect to database: ", $DBI::errstr;

    return;
}

sub psql_full {
    my ($self, @cmd_before, @cmd_after, @filenames) = @_;

    my ($fh, $fn) = tempfile undef, UNLINK => 1;
    $fh->autoflush(1);

    $self->_connect unless $self->{_dbh}->{Active};
    my ($dbname, $dbuser, $dbhost, $dbport, $dbpass) = @{$self->{_dbh}}{qw/pg_db pg_ user pg_host pg_port pg_pass/};

    local @ENV{qw/PGPASSFILE PGHOST PGPORT PGDATABASE PGUSER/} = ($fn, $dbhost, $dbport, $dbname, $dbuser);
    print $fh "$dbhost:$dbport:$dbname:$dbuser:$dbpass\n";

    local $SIG{PIPE} = 'IGNORE';

    my $pid = open my $psql_in, '|-';    ## no critic
    die "Cannot start psql: $!\n" unless defined $pid;
    unless ($pid) {
        open STDOUT, '>', '/dev/null' or warn "Cannot open /dev/null: $!\n";
        exec qw/psql -q -v ON_ERROR_STOP=1/;
        warn "Cannot exec psql: $!\n";
        CORE::exit 254;
    }

    print $psql_in "SET client_min_messages TO warning;\n" or die "Cannot write to psql: $!\n";
    if ($cmd_before) {
    	 print $psql_in "$cmd_before;\n" or die "Cannot write to psql: $!\n";
    }
    for my $name (@filenames) {
        print $psql_in "\\i $name\n" or die "Cannot write to psql: $!\n";
    }
    if ($cmd_after) {
    	 print $psql_in "$cmd_after;\n" or die "Cannot write to psql: $!\n";
    }
    close $psql_in and return;

    $! and die "Cannot write to psql: $!\n";

    my $sig = $? & 0x7f;    # ignore the highest bit which indicates a coredump
    die "psql killed by signal $sig" if $sig;

    my $rc = $? >> 8;
    die "psql returns 1 (out of memory, file not found or similar)\n" if $rc == 1;
    die "psql returns 2 (connection problem)\n"                       if $rc == 2;
    die "psql returns 3 (script error)\n"                             if $rc == 3;
    die "cannot exec psql\n"                                          if $rc == 254;
    die "psql returns unexpected code $rc\n";
}

sub psql {
    my ($self, @filenames) = @_;

    return $self->psql_full(undef, undef, @filenames)
}

sub _create_migration_table {
    my $self = shift;

    my $extra_sql = $self->dsn =~ /Pg/ ? 'SET client_min_messages = warning;' : '';
    my $tablename = $self->_tablename;
    $self->{_dbh}->do(<<"EOF");
$extra_sql
CREATE TABLE $tablename (
    name VARCHAR(64) PRIMARY KEY,
    value VARCHAR(64)
);
EOF
    $self->{_dbh}->do(<<"EOF");
    INSERT INTO $tablename ( name, value ) VALUES ( 'version', '0' );
EOF

    return;
}

sub _disconnect {
    my $self = shift;
    $self->{_dbh}->disconnect;

    return;
}

sub _files {
    my ($self, $type, $need) = @_;
    my @files;
    for my $i (@$need) {
        my $dir = $self->dir;
        opendir(DIR, $dir) or die "opening _files dir $dir: $!";
        while (my $file = readdir(DIR)) {
            # There is another change, previously this line was a comparision like:
            # $file =~ /${i}_$type\.sql$/.
            # It was including all files like .-test_10_up.sql in the list.
            # As some editors create these kind of files in the directory when editing a file
            # it was making trouble.
            # This is a small patch with as little change as possible until we can find the author or
            # become maintaner of the code in CPAN.
            next unless $file =~ /^schema_${i}_$type\.sql$/;
            $file = File::Spec->catdir($self->dir, $file);
            push @files,
                {
                name    => $file,
                version => $i
                };
        }
        closedir(DIR);
    }
    return unless @$need == @files;

    if (@files) {
        return \@files;
    } else {
        return;
    }
}

sub _newest {
    my $self   = shift;
    my $newest = 0;

    my $dir = $self->dir;
    opendir(DIR, $dir) or die "opening _newest dir $dir: $!";
    while (my $file = readdir(DIR)) {
        next unless $file =~ /^schema_(\d+)_up\.sql$/;
        $newest = $1 if $1 > $newest;
    }
    closedir(DIR);

    return $newest;
}

sub _update_migration_table {
    my ($self, $version) = @_;
    my $tablename = $self->_tablename;
    $self->{_dbh}->do(<<"EOF");
UPDATE $tablename SET value = '$version' WHERE name = 'version';
EOF

    return;
}

sub _version {
    my $self      = shift;
    my $version   = undef;
    my $tablename = $self->_tablename;
    try {
        my $sth = $self->{_dbh}->prepare(<<"EOF");
SELECT value FROM $tablename WHERE name = ?;
EOF
        $sth->execute('version');
        for my $val ($sth->fetchrow_arrayref) {
            $version = $val->[0];
        }
    };
    return $version;
}

=back

=head1 AUTHOR

Sebastian Riedel, C<sri@oook.de>

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;

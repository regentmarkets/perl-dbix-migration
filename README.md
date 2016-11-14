[![Build Status](https://travis-ci.org/binary-com/perl-dbix-migration.svg?branch=master)](https://travis-ci.org/binary-com/perl-dbix-migration)
[![codecov](https://codecov.io/gh/binary-com/perl-dbix-migration/branch/master/graph/badge.svg)](https://codecov.io/gh/binary-com/perl-dbix-migration)

# VERY IMPORTANT NOTE

    schema_branch is a concept to let Migration package work on several branch AND main branch of schema changes.
    In some situations like that we want to maintain several DB and not all of them need the same set of changes,
    those INDEPENDENT changes can go to a branch.

    Like when we have a report DB and that DB need many specific indices and extra defined functions to work we can create "report" schema branch for that reason.

    Branch directory lives is a sub-dir of main directory.

    branch changes should be applied after main changes.

    branch depends on main schemas but NO MAIN SCHEMA CHANGE-SET should depend on any branch schema.

# VERY IMPORTANT NOTE

        This package is actually DBIx::Migration package from cpan.

        I have contacted the maintainer of the package and I will try to become maintainer of this package if there was no answer.

        As soon as the bug is fixed in the main package we must get rid of this local package and use the cpan module instead.

        BUG: The bug was because of split/;/. In the main package split based on ";" breaks the file into parts that are not valid for postgres functions.

        ORIGINAL version: "0.05"

# NAME

DBIx::Migration - Seamless DB schema up- and downgrades

# SYNOPSIS

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

# DESCRIPTION

Seamless DB schema up- and downgrades.

# METHODS

- $self->debug($debug)

    Enable/Disable debug messages.

- $self->dir($dir)

    Get/Set directory.

- $self->dsn($dsn)

    Get/Set dsn.

- $self->migrate($version)

    Migrate database to version.

- $self->password

    Get/Set database password.

- $self->username($username)

    Get/Set database username.

- $self->version

    Get migration version from database.

# AUTHOR

Sebastian Riedel, `sri@oook.de`

# COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

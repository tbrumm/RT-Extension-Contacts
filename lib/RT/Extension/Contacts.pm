package RT::Extension::Contacts;

our $VERSION = '1.0.0';

use strict;
use warnings;

RT->AddStyleSheets('contacts.css');
RT->AddJavaScript('contacts.js');

RT::System->AddRight( Staff => SeeContacts            => 'View the Contacts page and search contacts' );   # loc
RT::System->AddRight( Staff => ManagePersonalContacts => 'Mark/unmark RT users as personal contacts' );      # loc
RT::System->AddRight( Staff => ManageGroupContacts    => 'Mark/unmark RT users as group contacts' );         # loc
RT::System->AddRight( Admin => AdminContacts          => 'Full access to contact markings and import/export' ); # loc

# Auto-create schema on first load
{
    my $dbh = $RT::Handle->dbh;
    eval {
        local $dbh->{PrintError} = 0;
        local $dbh->{RaiseError} = 1;
        $dbh->do(q{
            CREATE TABLE IF NOT EXISTS contact_markings (
                id            INTEGER NOT NULL AUTO_INCREMENT,
                user_id       INTEGER NOT NULL,
                marked_by     INTEGER NOT NULL,
                marking_type  VARCHAR(16) NOT NULL DEFAULT 'personal',
                group_id      INTEGER NOT NULL DEFAULT 0,
                notes         TEXT,
                created       DATETIME NOT NULL,
                last_updated  DATETIME NOT NULL,
                PRIMARY KEY (id),
                UNIQUE KEY uniq_marking (user_id, marked_by, marking_type, group_id),
                INDEX idx_marked_by (marked_by),
                INDEX idx_user_id   (user_id),
                INDEX idx_group_id  (group_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        });
    };
    RT::Logger->warning("RT::Extension::Contacts: could not create schema: $@") if $@;
}

# --- Helper functions ---

sub GetPersonalContacts {
    my ( $class, $viewer_id ) = @_;
    my $dbh = $RT::Handle->dbh;
    my $sth = $dbh->prepare(q{
        SELECT user_id, notes FROM contact_markings
        WHERE marked_by = ? AND marking_type = 'personal'
        ORDER BY created DESC
    });
    $sth->execute($viewer_id);
    return $sth->fetchall_arrayref({});
}

sub GetGroupContacts {
    my ( $class, $group_id, $viewer_id ) = @_;
    my $dbh = $RT::Handle->dbh;
    my $sth = $dbh->prepare(q{
        SELECT user_id, notes FROM contact_markings
        WHERE group_id = ? AND marking_type = 'group'
        ORDER BY created DESC
    });
    $sth->execute($group_id);
    return $sth->fetchall_arrayref({});
}

sub GetContactMarkings {
    my ( $class, $user_id, $viewer_id ) = @_;
    my $dbh = $RT::Handle->dbh;
    my $sth = $dbh->prepare(q{
        SELECT cm.*, u.Name AS marked_by_name,
               COALESCE(g.Name, '') AS group_name
        FROM contact_markings cm
        JOIN Users u ON u.id = cm.marked_by
        LEFT JOIN Groups g ON g.id = cm.group_id
        WHERE cm.user_id = ?
          AND (cm.marked_by = ? OR cm.marking_type = 'group')
        ORDER BY cm.marking_type, cm.created DESC
    });
    $sth->execute( $user_id, $viewer_id );
    return $sth->fetchall_arrayref({});
}

sub IsPersonalContact {
    my ( $class, $contact_user_id, $viewer_id ) = @_;
    my $dbh = $RT::Handle->dbh;
    my ($count) = $dbh->selectrow_array(q{
        SELECT COUNT(*) FROM contact_markings
        WHERE user_id = ? AND marked_by = ? AND marking_type = 'personal'
    }, undef, $contact_user_id, $viewer_id );
    return $count > 0;
}

sub IsGroupContact {
    my ( $class, $contact_user_id, $group_id ) = @_;
    my $dbh = $RT::Handle->dbh;
    my ($count) = $dbh->selectrow_array(q{
        SELECT COUNT(*) FROM contact_markings
        WHERE user_id = ? AND group_id = ? AND marking_type = 'group'
    }, undef, $contact_user_id, $group_id );
    return $count > 0;
}

sub AddPersonalContact {
    my ( $class, $contact_user_id, $viewer_id, $notes ) = @_;
    $notes //= '';
    my $dbh  = $RT::Handle->dbh;
    my $now  = _Now();
    eval {
        $dbh->do(q{
            INSERT INTO contact_markings (user_id, marked_by, marking_type, group_id, notes, created, last_updated)
            VALUES (?, ?, 'personal', 0, ?, ?, ?)
        }, undef, $contact_user_id, $viewer_id, $notes, $now, $now );
    };
    return $@ ? (0, $@) : (1, '');
}

sub RemovePersonalContact {
    my ( $class, $contact_user_id, $viewer_id ) = @_;
    my $dbh = $RT::Handle->dbh;
    $dbh->do(q{
        DELETE FROM contact_markings
        WHERE user_id = ? AND marked_by = ? AND marking_type = 'personal'
    }, undef, $contact_user_id, $viewer_id );
    return 1;
}

sub AddGroupContact {
    my ( $class, $contact_user_id, $group_id, $adder_id, $notes ) = @_;
    $notes //= '';
    my $dbh = $RT::Handle->dbh;
    my $now = _Now();
    eval {
        $dbh->do(q{
            INSERT INTO contact_markings (user_id, marked_by, marking_type, group_id, notes, created, last_updated)
            VALUES (?, ?, 'group', ?, ?, ?, ?)
        }, undef, $contact_user_id, $adder_id, $group_id, $notes, $now, $now );
    };
    return $@ ? (0, $@) : (1, '');
}

sub RemoveGroupContact {
    my ( $class, $contact_user_id, $group_id ) = @_;
    my $dbh = $RT::Handle->dbh;
    $dbh->do(q{
        DELETE FROM contact_markings
        WHERE user_id = ? AND group_id = ? AND marking_type = 'group'
    }, undef, $contact_user_id, $group_id );
    return 1;
}

sub GetUserGroups {
    my ( $class, $user_id ) = @_;
    my $groups = RT::Groups->new( RT->SystemUser );
    $groups->LimitToUserDefinedGroups();
    $groups->WithMember( PrincipalId => $user_id, Recursively => 0 );
    my @result;
    while ( my $g = $groups->Next ) {
        push @result, { id => $g->Id, name => $g->Name };
    }
    return \@result;
}

sub GetRecentTickets {
    my ( $class, $contact_user_id, $limit ) = @_;
    $limit //= 10;
    my $user = RT::User->new( RT->SystemUser );
    $user->Load($contact_user_id);
    return [] unless $user->Id;

    my $tickets = RT::Tickets->new( RT->SystemUser );
    $tickets->FromSQL(
        "Requestor = '" . $user->EmailAddress . "'"
        . " OR Owner = '" . $user->Name . "'"
    );
    $tickets->OrderBy( FIELD => 'LastUpdated', ORDER => 'DESC' );
    $tickets->RowsPerPage($limit);

    my @result;
    while ( my $t = $tickets->Next ) {
        push @result, {
            id      => $t->Id,
            subject => $t->Subject,
            status  => $t->Status,
            queue   => $t->QueueObj->Name,
        };
    }
    return \@result;
}

sub GetRecentAssets {
    my ( $class, $contact_user_id, $limit ) = @_;
    $limit //= 5;
    my $dbh = $RT::Handle->dbh;
    my $rows = $dbh->selectall_arrayref(q{
        SELECT a.id, a.Name, a.Status, c.Name AS catalog
        FROM Assets a
        JOIN Groups g  ON g.Instance = a.id
                      AND g.Domain   = 'RT::Asset-Role'
                      AND g.Name     = 'HeldBy'
        JOIN GroupMembers gm ON gm.GroupId = g.id
        JOIN Catalogs c ON c.id = a.Catalog
        WHERE gm.MemberId = ?
          AND a.Status != 'deleted'
        ORDER BY a.LastUpdated DESC
        LIMIT ?
    }, { Slice => {} }, $contact_user_id, $limit );
    return $rows // [];
}

sub GetRecentArticles {
    my ( $class, $contact_user_id, $limit ) = @_;
    $limit //= 5;

    my $articles = RT::Articles->new( RT->SystemUser );
    $articles->Limit( FIELD => 'LastUpdatedBy', VALUE => $contact_user_id );
    $articles->OrderBy( FIELD => 'LastUpdated', ORDER => 'DESC' );
    $articles->RowsPerPage($limit);

    my @result;
    while ( my $a = $articles->Next ) {
        push @result, {
            id      => $a->Id,
            name    => $a->Name,
            summary => $a->Summary,
            class   => $a->ClassObj->Name,
        };
    }
    return \@result;
}

sub SearchUsers {
    my ( $class, $query, $limit ) = @_;
    $limit //= 50;
    $query //= '';
    $query =~ s/[^\w\s\@\.\-]//g;

    my $users = RT::Users->new( RT->SystemUser );
    $users->LimitToEnabled();
    if ( length $query ) {
        $users->Limit( FIELD => 'Name',         VALUE => "%$query%", OPERATOR => 'LIKE', SUBCLAUSE => 'search', ENTRYAGGREGATOR => 'OR' );
        $users->Limit( FIELD => 'RealName',     VALUE => "%$query%", OPERATOR => 'LIKE', SUBCLAUSE => 'search', ENTRYAGGREGATOR => 'OR' );
        $users->Limit( FIELD => 'EmailAddress', VALUE => "%$query%", OPERATOR => 'LIKE', SUBCLAUSE => 'search', ENTRYAGGREGATOR => 'OR' );
    }
    $users->OrderBy( FIELD => 'RealName', ORDER => 'ASC' );
    $users->RowsPerPage($limit);
    return $users;
}

sub GetAllContacts {
    my ( $class, $limit, $offset ) = @_;
    $limit  //= 50;
    $offset //= 0;
    my $users = RT::Users->new( RT->SystemUser );
    $users->LimitToEnabled();
    $users->OrderBy( FIELD => 'RealName', ORDER => 'ASC' );
    $users->RowsPerPage($limit);
    $users->FirstRow( $offset + 1 ) if $offset;
    return $users;
}

sub ExportCSV {
    my ( $class, $rows ) = @_;
    my @cols = qw(id name email realname organization phone mobile marking_type group notes);
    my $csv = join(',', @cols) . "\n";
    for my $row (@$rows) {
        $csv .= join(',', map { _csv_field($row->{$_} // '') } @cols) . "\n";
    }
    return $csv;
}

sub _csv_field {
    my $v = shift;
    $v =~ s/"/""/g;
    return qq{"$v"};
}

sub _Now {
    my @t = localtime;
    return sprintf '%04d-%02d-%02d %02d:%02d:%02d',
        $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0];
}

=head1 NAME

RT::Extension::Contacts - Contact management for Request Tracker 6

=head1 DESCRIPTION

Adds a Contacts page under Tools with personal and group contact management.
Contacts are standard RT users; this extension adds marking metadata only.

=head1 RIGHTS

=over 4

=item SeeContacts - View the Contacts page

=item ManagePersonalContacts - Manage own personal contacts

=item ManageGroupContacts - Manage group contacts for own groups

=item AdminContacts - Full administrative access

=back

=head1 CONFIGURATION

  Plugin('RT::Extension::Contacts');

=cut

1;

use v6;

use Crypt::Random;
use Crypt::Random::Extra;
use Digest::SHA1::Native;

use Agrammon::DB;
use Agrammon::DB::Role;

class X::Agrammon::DB::User::Exists is Exception {
    has $.username;
    method message() {
        "Account $!username already exists!";
    }
}

class X::Agrammon::DB::User::NoUsername is Exception {
    method message() {
        "Need username to load user from database!";
    }
}

class X::Agrammon::DB::User::CannotSetRole is Exception {
    method message() {
        "Only admin users can create accounts with roles!";
    }
}

class X::Agrammon::DB::User::CannotResetPassword is Exception {
    method message() {
        "Only admin users can reset other users' password!";
    }
}

class X::Agrammon::DB::User::CreateFailed is Exception {
    has Str $.username is required;
    method message {
        "Couldn't create user $!username";
    }
}

class X::Agrammon::DB::User::ActivationFailed is Exception {
    method message {
        "Couldn't activate account";
    }
}

class X::Agrammon::DB::User::NoPassword is Exception {
    method message() {
        "Need password to create an account!";
    }
}

class X::Agrammon::DB::User::UnknownRole is Exception {
    has Str $.role is required;
    method message {
        "Role '$!role' doesn't exist.";
    }
}

class X::Agrammon::DB::User::PasswordResetFailed is Exception {
    method message() {
        "Invalid username or password";
    }
}

class X::Agrammon::DB::User::InvalidLogin is Exception {
    method message() {
        "Invalid username or password";
    }
}

class X::Agrammon::DB::User::InvalidPassword is Exception {
    method message() {
        "Password does not fit requirements";
    }
}

class X::Agrammon::DB::User::UnknownUser is Exception {
    has Str $.username is required;
    method message() {
        "User '$!username' has no Agrammon account";
    }
}

class X::Agrammon::DB::User::MayNotSudo is Exception {
    has Str $.username is required;
    method message() {
        "User '$!username' may not change to another account";
    }
}

class X::Agrammon::DB::User::PasswordsIdentical is Exception {
    method message() {
        "Old and new password must be different";
    }
}

class Agrammon::DB::User does Agrammon::DB {
    has Int $.id;
    has Str $.username;
    has Str $.password;
    has $.firstname;
    has $.lastname;
    has $.organisation;
    has DateTime $.last-login;
    has DateTime $.created;
    has Agrammon::DB::Role $.role;

    method set-username(Str $username) {
        $!username = $username;
    }

    method is-admin {
        $!role.is-admin
    }

    my $secret = crypt_random(Int(64/8));
    my $encrypt-key = 'jah7Eiyitui1Zibe';

    sub get-password-key($username, $password) {
        my $digest = sha1-hex($username ~ $password ~ $secret);
        return $digest;
    }

    method get-account-key() {
        die X::Agrammon::DB::User::NoUsername.new(:$!username) unless $!username;
        die X::Agrammon::DB::User::NoPassword.new unless $!password;

        get-password-key($!username, $!password)
    }

    method create-account($role-name) {
        my $role = $role-name || 'user';
        die X::Agrammon::DB::User::Exists.new(:$!username) if self.exists;
        die X::Agrammon::DB::User::NoUsername.new(:$!username) unless $!username;
        die X::Agrammon::DB::User::InvalidPassword.new unless password-allowed($!password);

        self.with-db: -> $db {
            my $ret = $db.query(q:to/SQL/, $role);
                SELECT role_id   AS id,
                       role_name AS name
                  FROM role
                 WHERE role_name = $1
            SQL
            die X::Agrammon::DB::User::UnknownRole.new(:$role) unless $ret.rows;

            my %r = $ret.hash;
            $!role = Agrammon::DB::Role.new(|%r);

            $ret = $db.query(q:to/SQL/, $!username, $!firstname, $!lastname, $!password, $!organisation, %r<id> );
                INSERT INTO pers (pers_email, pers_first, pers_last,
                                  pers_password, pers_org, pers_role, pers_activated)
                VALUES ($1, $2, $3, crypt($4, gen_salt('bf')), $5, $6, now())
                RETURNING pers_id
            SQL

            die X::Agrammon::DB::User::CreateFailed.new(:$!username) unless $ret.rows;
        }
        return self;
    }

    # we set a random password (must be NOT NULL)
    # and save the encrypted password and the activation key
    method self-create-account($role-name) {
        my $role = $role-name || 'user';
        die X::Agrammon::DB::User::Exists.new(:$!username) if self.exists;
        die X::Agrammon::DB::User::NoUsername.new(:$!username) unless $!username;
        die X::Agrammon::DB::User::InvalidPassword.new unless password-allowed($!password);

        my $key;

        self.with-db: -> $db {
            my $ret = $db.query(q:to/SQL/, $role);
                SELECT role_id   AS id,
                       role_name AS name
                  FROM role
                 WHERE role_name = $1
            SQL
            die X::Agrammon::DB::User::UnknownRole.new(:$role) unless $ret.rows;

            my %r = $ret.hash;
            $!role = Agrammon::DB::Role.new(|%r);
            $key = self.get-account-key();
            $ret = $db.query(q:to/SQL/, $!username, $!firstname, $!lastname, $!organisation, %r<id>, $!password, $encrypt-key, $key );
                INSERT INTO pers (pers_email, pers_first, pers_last,
                                  pers_password,
                                  pers_org, pers_role,
                                  pers_newpassword, pers_newpassword_key
                                 )
                VALUES ($1, $2, $3,
                        gen_random_uuid(), -- random password until activated
                        $4, $5,
                        encode(encrypt($6, $7, 'aes'), 'base64'), $8
                       )
                RETURNING pers_id
            SQL

            die X::Agrammon::DB::User::CreateFailed.new(:$!username) unless $ret.rows;

            $!id = $ret.value;
        }
        return $key;
    }

    # set the real password
    method activate-account($key) {
        # note "User: Activating account with key $key";
        self.with-db: -> $db {
            my $ret = $db.query(q:to/SQL/, $key, $encrypt-key, DateTime.now);
                UPDATE pers SET pers_password = crypt(convert_from(decrypt(decode(pers_newpassword, 'base64'), $2, 'aes'), 'UTF-8'), gen_salt('bf')),
                                pers_activated = $3,
                                pers_password_changed = $3,
                                pers_newpassword = NULL, pers_newpassword_key = NULL
                 WHERE pers_newpassword_key = $1
                RETURNING pers_email
            SQL

            $!username = $ret.value if $ret.rows;
            note "Account activated for $!username";
        }
        self.load if $!username;
        return self;
    }

    method load() {
        die X::Agrammon::DB::User::NoUsername.new unless $!username;
        self.with-db: -> $db {
            my $u = $db.query(q:to/USER/, $!username).hash;
                SELECT pers_id         AS id,
                       pers_email      AS username,
                       pers_first      AS firstname,
                       pers_last       AS lastname,
                       pers_password   AS password,
                       pers_org        AS organisation,
                       pers_last_login AS "last-login",
                       pers_created    AS created,
                       pers_role       AS "role-id"
                  FROM pers
                 WHERE pers_email = $1
            USER

            # how can this be done more compactly
            $!id           = $u<id>;
            $!username     = $u<username>;
            $!firstname    = $u<firstname>;
            $!lastname     = $u<lastname>;
            $!organisation = $u<organisation>;
            $!last-login   = $u<last-login>;
            $!created      = $u<created>;

            my %r = $db.query(q:to/ROLE/, $u<role-id>).hash;
                SELECT role_id   AS id,
                       role_name AS name
                  FROM role
                 WHERE role_id = $1
            ROLE
            $!role = Agrammon::DB::Role.new(|%r);
        }
        return self;
    }

    method exists() {
        my $uid;
        self.with-db: -> $db {
            $uid = $db.query(q:to/USER/, $!username).value;
                SELECT pers_id AS id
                  FROM pers
                 WHERE pers_email = $1
            USER
        }
        return $uid;
    }

    method password-is-valid(Str $username, Str $password) {
        self.with-db: -> $db {
            return $db.query(q:to/SQL/, $username, $password).value;
                SELECT crypt($2, pers_password) = pers_password
                  FROM pers
                 WHERE pers_email = $1
            SQL
        }
    }

    method change-password($old, $new) {
        self.with-db: -> $db {

            die X::Agrammon::DB::User::InvalidLogin.new    unless self.password-is-valid($!username, $old);
            die X::Agrammon::DB::User::PasswordsIdentical.new if $old eq $new;
            die X::Agrammon::DB::User::InvalidPassword.new unless password-allowed($new);

            $db.query(q:to/SQL/, $!username, $new);
                UPDATE pers
                    SET pers_password = crypt($2, gen_salt('bf'))
                    WHERE pers_email  = $1
                RETURNING pers_email
            SQL

            die X::Agrammon::DB::User::InvalidLogin.new unless self.password-is-valid($!username, $new);
        }
    }

    sub password-key-is-valid(Str $username, Str $password, Str $key) {
        get-password-key($username, $password) eq $key
    }

    sub password-allowed(Str $password) {
        return False if $password.chars < 8;
        return True;
    }

    method reset-password($email, $password, $key?) {
        # self reset, anonymous user
        if $key and not password-key-is-valid($email, $password, $key) {
            die X::Agrammon::DB::User::CannotResetPassword.new;
        }
        die X::Agrammon::DB::User::InvalidPassword.new unless password-allowed($password);

        self.with-db: -> $db {
            $db.query(q:to/SQL/, $email, $password);
                UPDATE pers
                   SET pers_password = crypt($2, gen_salt('bf'))
                 WHERE pers_email = $1
                RETURNING pers_email
                SQL
            die X::Agrammon::DB::User::PasswordResetFailed.new unless self.password-is-valid($email, $password);
        }
    }

    method self-reset-password($new-password) {
        die X::Agrammon::DB::User::InvalidPassword.new unless password-allowed($new-password);

        # self reset, anonymous user
        my $email = $!username;
        my $key = self.get-account-key();

        self.with-db: -> $db {
            my $ret = $db.query(q:to/SQL/, $email, $new-password, $encrypt-key, $key);
                UPDATE pers
                   SET pers_newpassword = encode(encrypt($2, $3, 'aes'), 'base64'),
                       pers_newpassword_key = $4
                 WHERE pers_email = $1
                RETURNING pers_email
                SQL

            die X::Agrammon::DB::User::PasswordResetFailed.new unless $ret.rows;
            note "User: confirmation key=$key";
        }
        return $key;
    }

}

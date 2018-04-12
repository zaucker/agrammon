use v6;
use Agrammon::DB;
use Agrammon::DB::Tag;
use Agrammon::DB::User;

class Agrammon::DB::Dataset does Agrammon::DB {
    has Int  $.id;
    has Str  $.name;
    has Bool $.read-only;
    has Str  $.model;
    has Str  $.comment;
    has Str  $.version;
    has Int  $.records;
    has DateTime $.mod-date;
    has Agrammon::DB::Tag  @.tags;
    has Agrammon::DB::User $.user;
    has $.data;
    
    method create {
        self.with-db: -> $db {
            my $ds = $db.query(q:to/DATASET/, $!name, $!user.id, $!version, $!comment, $!model, $!read-only);
                INSERT INTO dataset (dataset_name, dataset_pers,
                                     dataset_version, dataset_comment,
                                     dataset_model, dataset_readonly
                                    )
                VALUES ($1, $2, $3, $4, $5, $6)
                RETURNING dataset_id, dataset_mod_date
            DATASET

            my @d = $ds.array;    
            $!id = @d[0];
            $!mod-date = @d[1];
        }
        return self;
    }

    method load {
        self.with-db: -> $db {
            my $username = $!user.username;
            my $results = $db.query(q:to/DATASET/, $username, $!name);
            SELECT data_var, data_val, data_instance_order, branches_data, data_comment
              FROM data_view LEFT JOIN branches ON (branches_var=data_id)
             WHERE data_dataset=dataset_name2id($1,$2)
               AND data_var not like '%::ignore'
             ORDER BY data_instance_order ASC, data_var
            DATASET
            $!data = $results.arrays;
        }
        return self;
    }

    method _store-variable($var, $value) {

        return unless $var and $value;
        my $username = $!user.username;
#        say "store_variable($!name, $username): var=$var, value=$value";
        
        my $ret;
        self.with-db: -> $db {
            $ret = $db.query(q:to/SQL/, $value, $username, $!name, $var);
            UPDATE data_new SET data_val = $1
             WHERE data_dataset=dataset_name2id($2,$3) AND data_var=$4
                                                       AND data_instance IS NULL
            RETURNING data_val 
            SQL

            my $rows = $ret.rows;
#            warn "_store-variable(UPDATE): rows=$rows";
            return $rows if $rows;

            $ret = $db.query(q:to/SQL/, $value, $username, $!name, $var);
            INSERT INTO data_new (data_dataset, data_var, data_val)
            VALUES (dataset_name2id($2,$3),$4,$1)
            RETURNING data_val
            SQL
            $rows = $ret.rows;
#            warn "_store-variable(INSERT): rows=$rows";
            return $rows if $rows;

        }
        return $ret;
    }

    method _store-instance-variable($var, $instance, $value) {

        return unless $var and $value and $instance;
        my $username = $!user.username;
#        say "store_variable($!name, $username): var=$var, instance=$instance, value=$value";
        
        my $ret;
        self.with-db: -> $db {
            $ret = $db.query(q:to/SQL/, $value, $username, $!name, $var, $instance);
            UPDATE data_new SET data_val = $1
             WHERE data_dataset=dataset_name2id($2,$3) AND data_var=$4
                                                       AND data_instance = $5
            RETURNING data_val 
           SQL
#           warn "_store-instance-variable() rows=", $ret.rows;
            
        }
        return $ret.rows;
    }
    
    method store-input($var-name, $value) {
        my $instance;

        my $var = $var-name;
        if $var ~~ s/\[(.+)\]/[]/ {
            $instance = $0;
        }

        my $ret = $instance ?? self._store-instance-variable($var, $instance, $value)
                            !! self._store-variable($var, $value);
        return $ret;
    }
    

}

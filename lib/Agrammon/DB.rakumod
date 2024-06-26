use v6;

role Agrammon::DB {
    method connection() { $*AGRAMMON-DB-CONNECTION }

    method with-db(&operation) {
        with $*AGRAMMON-DB-CONNECTION {
            operation($*AGRAMMON-DB-CONNECTION);
        }
        else {
            note "Using fresh DB handle";
            self!with-fresh-handle(&operation);
        }
    }

    method !with-fresh-handle(&operation) {
        my $handle = self.connection.db;
        my $*AGRAMMON-DB-CONNECTION = $handle;
        my \result := operation($handle);
        $handle.finish;
        return result;
        CATCH {
            .finish with $handle;
        }
    }
}

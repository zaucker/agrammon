use v6;
use Net::SMTP::Client::Async;
use Email::MIME;

class Agrammon::Email {
    has $!msg;
    has $!subject;
    has $!to;
    has $!from;
    has $!attachment;
    has $!mail;

    submethod TWEAK( :$!to!, :$!from!, :$!subject!, :$msg!, :$attachment, :$filename = 'agrammon.pdf' --> Nil) {
        if $attachment {
            $!attachment = Email::MIME.create(
                attributes => {
                    'content-type' => "application/pdf; name=$filename",
                    'charset'      => 'utf-8',
                    'encoding'     => 'base64',
                },
                body => $attachment,
            );
        }
        $!msg = Email::MIME.create(
            attributes => {
                'content-type' => 'text/plain',
                'charset'      => 'utf-8',
                'encoding'     => 'quoted-printable'
            },
            body-str => $msg,
        );
        $!mail = Email::MIME.create(
            header-str => [
                'to'      => $!to,
                'from'    => $!from,
                'subject' => $!subject
            ],
            parts => [
                $!msg,
                $!attachment,
            ]
        );
    }

    method mail {
        $!mail
    }

    method send {
        with await Net::SMTP::Client::Async.connect(:host<mail.oetiker.ch>, :port(25), :!secure) {
            await .hello;

            await .send-message(
                :$!from,
                :to([ $!to ]),
                :message(~$!mail),
            );

            LEAVE .quit;

            CATCH {
                when X::Net::SMTP::Client::Async {
                    note "Unable to send email message: $_";
                }
            }
        }
    }

}

use strict;
use warnings;
use autodie;
use Test::More tests => 20;
use Net::Stripe::Simple qw(:all);
use DateTime;

note '!!!!!!';
note "NOTE:\nIf you do not have an Internet connection, "
  . "or cannot see Stripe's API from this connection, this test will fail.";
note '!!!!!!';

# test key from Stripe's API documentation
my $stripe = new_ok( 'Net::Stripe::Simple' =>
      [ 'sk_test_BQokikJOvBiI2HlWgH4olfQ2', '2014-06-17' ] );

my $time = time;
my $customer;
subtest Customers => sub {
    plan tests => 7;
    $customer = $stripe->customers(
        create => {
            metadata => { foo => 'bar' }
        }
    );
    ok defined($customer) && $customer->metadata->foo eq 'bar',
      'created a customer';
    $customer = $stripe->customers(
        update => {
            id       => $customer,
            metadata => { foo => 'baz' }
        }
    );
    ok defined($customer) && $customer->metadata->foo eq 'baz',
      'updated a customer';
    my $customers = $stripe->customers(
        list => {
            created => { gte => $time - 100 }
        }
    );
    ok defined $customers, 'listed customers';
    ok( ( grep { $_->id eq $customer->id } @{ $customers->data } ),
        'new customer listed' );
    my $id = $customer->id;
    $customer = $stripe->customers( retrieve => $id );
    ok defined($customer) && $customer->id eq $id, 'simple retrieve';
    $customer = $stripe->customers( retrieve => { id => $id } );
    ok defined($customer) && $customer->id eq $id, 'verbose retrieve';
    $customer = $stripe->customers( delete => $id );
    ok defined($customer) && $customer->deleted, 'deleted customer';

    # recreate customer for use in other tests
    $customer = $stripe->customers(
        create => {
            metadata => { foo => 'bar' }
        }
    );
};

my $card;
my $expiry = DateTime->now->add( years => 1 );
subtest Cards => sub {
    plan tests => 5;
    $card = $stripe->cards(
        create => {
            customer => $customer,
            card     => {
                number    => '4242424242424242',
                exp_month => $expiry->month,
                exp_year  => $expiry->year,
                cvc       => 123
            }
        }
    );
    ok defined($card) && $card->customer eq $customer->id,
      'created a card for a customer';
    $card = $stripe->cards(
        update => {
            customer => $customer,
            id       => $card,
            name     => 'foo',
        }
    );
    is $card->name, 'foo', 'updated a card';
    my $id = $card->id;
    $card = $stripe->cards(
        retrieve => {
            customer => $customer,
            id       => $id
        }
    );
    ok defined($card) && $card->id eq $id, 'retrieved a card';
    my $cards = $stripe->cards( list => $customer );
    ok(
        (
                  defined $cards
              and @{ $cards->data } == 1
              and $cards->data->[0]->id eq $id
        ),
        'listed cards'
    );
    $card = $stripe->cards(
        delete => {
            customer => $customer,
            id       => $id
        }
    );
    ok defined($card) && $card->deleted, 'deleted a card';

    # recreate card for later use
    $card = $stripe->cards(
        create => {
            customer => $customer,
            card     => {
                number    => '4242424242424242',
                exp_month => $expiry->month,
                exp_year  => $expiry->year,
                cvc       => 123
            }
        }
    );
};

my $charge;
subtest Charges => sub {
    $charge = $stripe->charges(
        create => {
            customer => $customer,
            amount   => 100,
            currency => 'usd',
            capture  => false,
        }
    );
    ok defined($charge) && !$charge->captured, 'created an uncaptured charge';
    $charge = $stripe->charges(
        update => {
            id          => $charge,
            description => 'foo',
        }
    );
    is $charge->description, 'foo', 'updated charge';
    my $id = $charge->id;
    $charge = $stripe->charges( retrieve => $id );
    is $charge->id, $id, 'retrieved a charge';
    $charge = $stripe->charges( capture => $id );
    ok $charge->captured, 'captured a charge';
    my $charges = $stripe->charges( list => {} );
    ok( ( grep { $_->id eq $charge->id } @{ $charges->data } ),
        'zero-arg list' );
    $charges = $stripe->charges( list => { customer => $customer } );
    ok( ( grep { $_->id eq $charge->id } @{ $charges->data } ),
        'multi-arg list' );
};

subtest Refunds => sub {
    plan tests => 4;
    my $refund = $stripe->refunds(
        create => {
            id     => $charge,
            amount => 50
        }
    );
    is $refund->object, 'refund', 'created a refund';
    $refund = $stripe->refunds(
        retrieve => {
            id     => $refund,
            charge => $charge
        }
    );
    is $refund->amount, 50, 'retrieved a refund';
    $refund = $stripe->refunds(
        update => {
            id       => $refund,
            charge   => $charge,
            metadata => { foo => 'bar' }
        }
    );
    is $refund->metadata->foo, 'bar', 'updated a refund';
    my $refunds = $stripe->refunds( list => $charge );
    ok( ( grep { $_->id eq $refund->id } @{ $refunds->data } ),
        'listed refunds' );
};

my ( $plan, $spare_plan );
subtest Plans => sub {
    plan tests => 5;
    my $id = $$ . 'foo' . time;
    $plan = $stripe->plans(
        create => {
            id       => $id,
            amount   => 100,
            currency => 'usd',
            interval => 'week',
            name     => 'Foo',
        }
    );
    is $plan->id, $id, 'created a plan';
    $plan = $stripe->plans( retrieve => $id );
    is $plan->id, $id, 'retrieved plan';
    $plan = $stripe->plans(
        update => {
            id       => $id,
            metadata => { bar => 'baz' }
        }
    );
    is $plan->metadata->bar, 'baz', 'updated plan';
    my $plans = $stripe->plans('list');
    ok scalar @{ $plans->data },
      'listed plans';    # this fake account may have many
    $plan = $stripe->plans( delete => $id );
    ok $plan->deleted, 'deleted a plan';

    # keep around
    $plan = $stripe->plans(
        create => {
            id       => $id,
            amount   => 100,
            currency => 'usd',
            interval => 'week',
            name     => 'Foo',
        }
    );
    $spare_plan = $stripe->plans(
        create => {
            id       => $$ . 'bar' . time,
            amount   => 100000,
            currency => 'usd',
            interval => 'week',
            name     => 'Bar',
        }
    );
};

my $subscription;
subtest Subscriptions => sub {
    plan tests => 5;
    $subscription = $stripe->subscriptions(
        create => {
            customer => $customer,
            plan     => $plan,
        }
    );
    is $subscription->plan->id, $plan->id, 'created a subscription';
    my $id = $subscription->id;
    $subscription = $stripe->subscriptions(
        retrieve => {
            id       => $id,
            customer => $customer,
        }
    );
    is $subscription->id, $id, 'retrieved a subscription';
    $subscription = $stripe->subscriptions(
        update => {
            id       => $id,
            customer => $customer,
            metadata => { foo => 'bar' }
        }
    );
    is $subscription->metadata->foo, 'bar', 'updated a subscription';
    my $subscriptions = $stripe->subscriptions( list => $customer );
    is $subscriptions->data->[0]->id, $id, 'listed subscriptions';
    $subscription = $stripe->subscriptions(
        cancel => {
            id       => $id,
            customer => $customer,
        }
    );
    is $subscription->status, 'canceled', 'canceled a subscription';

    # burden this customer with a subscription again
    $subscription = $stripe->subscriptions(
        create => {
            customer => $customer,
            plan     => $plan,
        }
    );
};

my $invoice;
subtest Invoices => sub {
    plan tests => 6;
    my $invoices = $stripe->invoices( list => { customer => $customer } );
    $invoice = $invoices->data->[0];
    is $invoice->customer, $customer->id, 'listed invoices for customer';
    my $id = $invoice->id;
    $invoice = $stripe->invoices( retrieve => $id );
    is $invoice->id, $id, 'retrieved specific invoice';
    $invoice = $stripe->invoices(
        update => {
            id       => $id,
            metadata => { foo => 'bar' }
        }
    );
    is $invoice->metadata->foo, 'bar', 'updated invoice';
    $stripe->subscriptions(
        update => {
            customer => $customer,
            id       => $subscription,
            plan     => $spare_plan,
        }
    );
    my $new_invoice = $stripe->invoices(
        create => {
            customer => $customer,
        }
    );
    $new_invoice = $stripe->invoices( pay => $new_invoice );
    ok $new_invoice->paid, 'paid invoice';
    $new_invoice = $stripe->invoices( upcoming => $customer );
    is $new_invoice->customer, $customer->id, 'retrieved an upcoming invoice';
    my $lines = $stripe->invoices( lines => $invoice );
    is $lines->object, 'list', 'retrieved line items for invoice';
};

subtest 'Invoice Items' => sub {
    plan tests => 5;
    my $new_invoice = $stripe->invoices( upcoming => $customer );
    my $item = $stripe->invoice_items(
        create => {
            customer => $customer,
            amount   => 100,
            currency => 'usd',
            metadata => { foo => 'bar' }
        }
    );
    is $item->metadata->foo, 'bar', 'created invoice item';
    my $id = $item->id;
    $item = $stripe->invoice_items( retrieve => $id );
    is $item->id, $id, 'retrieved invoice item';
    $item = $stripe->invoice_items(
        update => {
            id       => $item,
            metadata => { foo => 'baz' }
        }
    );
    is $item->metadata->foo, 'baz', 'updated invoice item';
    my $items = $stripe->invoice_items( list => { customer => $customer } );
    ok( ( grep { $_->id eq $item->id } @{ $items->data } ),
        'listed invoice items' );
    $item = $stripe->invoice_items( delete => $item );
    ok $item->deleted, 'deleted invoice item';
};

my $coupon;
subtest Coupons => sub {
    plan tests => 4;
    $coupon = $stripe->coupons(
        create => {
            percent_off => 1,
            duration    => 'forever',
        }
    );
    is $coupon->duration, 'forever', 'created a coupon';
    my $id = $coupon->id;
    $coupon = $stripe->coupons( retrieve => $id );
    is $coupon->id, $id, 'retrieved coupon';
    my $coupons = $stripe->coupons('list');
    ok scalar @{ $coupons->data }, 'listed coupons';
    $coupon = $stripe->coupons( delete => $coupon );
    ok $coupon->deleted, 'deleted a coupon';
    $coupon = $stripe->coupons(
        create => {
            percent_off => 1,
            duration    => 'forever',
        }
    );
};

subtest Discounts => sub {
    plan tests => 2;
    my $c = $stripe->customers(
        create => {
            metadata => { foo => 'bar' },
            coupon   => $coupon,
        }
    );
    my $card = $stripe->cards(
        create => {
            customer => $c,
            card     => {
                number    => '4242424242424242',
                exp_month => $expiry->month,
                exp_year  => $expiry->year,
                cvc       => 123
            }
        }
    );
    my $s = $stripe->subscriptions(
        create => {
            customer => $c,
            plan     => $plan,
            coupon   => $coupon,
        }
    );
    my $deleted = $stripe->discounts( customer => $c );
    ok $deleted->deleted, 'deleted a customer discount';
    $deleted = $stripe->discounts(
        subscription => {
            customer     => $c,
            subscription => $s,
        }
    );
    ok $deleted->deleted, 'deleted a subscription discount';
    $stripe->subscriptions(
        cancel => {
            id       => $s,
            customer => $c,
        }
    );
    $stripe->customers( delete => $c );
};

subtest Disputes => sub {
    plan tests => 2;

    # we don't actually have any disputes, but this will suffice to confirm
    # that we are calling the API correctly
    eval {
        $stripe->disputes(
            update => {
                id       => $charge,
                metadata => { foo => 'bar' }
            }
        );
    };
    my $e = $@;
    is $e->message, "No dispute for charge: $charge", 'updated a dispute';
    eval { $stripe->disputes( close => $charge ); };
    $e = $@;
    is $e->message, "No dispute for charge: $charge", 'closed a dispute';
};

my $token;
subtest Tokens => sub {
    plan tests => 4;
    $token = $stripe->tokens(
        create => {
            card => {
                number    => '4242424242424242',
                exp_month => $expiry->month,
                exp_year  => $expiry->year,
                cvc       => 123
            }
        }
    );
    is $token->type, 'card', 'created a card token';
    $token = $stripe->tokens(
        bank => {
            bank_account => {
                country        => 'US',
                routing_number => '110000000',
                account_number => '000123456789',
            }
        }
    );
    is $token->type, 'bank_account', 'created a bank account token with bank';
    $token = $stripe->tokens(
        create => {
            bank_account => {
                country        => 'US',
                routing_number => '110000000',
                account_number => '000123456789',
            }
        }
    );
    is $token->type, 'bank_account', 'created a bank account token with create';
    my $id = $token->id;
    $token = $stripe->tokens( retrieve => $id );
    is $token->id, $id, 'retrieved a token';
};

my $recipient;
subtest Recipients => sub {
    plan tests => 5;
    $recipient = $stripe->recipients(
        create => {
            name => 'I Am An Example',
            type => 'individual',
        }
    );
    ok $recipient, 'created a recipient';
    my $id = $recipient->id;
    $recipient = $stripe->recipients( retrieve => $id );
    is $recipient->id, $id, 'retrieved recipient';
    my $recipients = $stripe->recipients('list');
    ok scalar @{ $recipients->data }, 'listed recipients';
    $recipient = $stripe->recipients(
        update => {
            id       => $recipient,
            metadata => { foo => 'bar' },
        }
    );
    is $recipient->metadata->foo, 'bar', 'updated recipient';
    $recipient = $stripe->recipients( delete => $id );
    ok $recipient->deleted, 'deleted recipient';
    $recipient = $stripe->recipients(
        create => {
            name         => 'I Am An Example',
            type         => 'individual',
            bank_account => $token,
        }
    );
};

subtest Transfers => sub {
    plan tests => 5;
    my $transfer = $stripe->transfers(
        create => {
            amount    => 1,
            currency  => 'usd',
            recipient => $recipient,
        }
    );
    ok $transfer, 'created a transfer';
    my $id = $transfer->id;
    $transfer = $stripe->transfers( retrieve => $id );
    is $transfer->id, $id, 'retrieved a transfer';
    my $transfers = $stripe->transfers(
        list => {
            created => { gt => $time }
        }
    );
    ok( ( grep { $_->id eq $id } @{ $transfers->data } ), 'listed transfers' );
    $transfer = $stripe->transfers(
        update => {
            id       => $transfer,
            metadata => { foo => 'bar' }
        }
    );
    is $transfer->metadata->foo, 'bar', 'updated a transfer';
    eval {
        $transfer = $stripe->transfers( cancel => $transfer );
        ok $transfer->canceled, 'canceled a transfer';
    };
    if ( my $e = $@ ) {    # at least the path worked
        ok $e->message =~
          /Transfer cannot be canceled, because it has already been submitted/,
          'canceled a transfer';
    }
};

subtest 'Application Fees' => sub {
    plan tests => 3;
    my $fees = $stripe->application_fees('list');
    ok $fees, 'listed application fees';
    my $id = 'fee_4KuzXIHPLEjY8n';    # borrowing from API
    eval {
        my $fee = $stripe->application_fees( retrieve => $id );
        is $fee->id, $id, 'retrieved application fee';
    };
    if ( my $e = $@ ) {               # at least the path worked
        is $e->message, "No such application fee: $id",
          'retrieved application fee';
    }
    eval {
        my $fee = $stripe->application_fees( refund => $id );
        is $fee->id, $id, 'refunded application fee';
    };
    if ( my $e = $@ ) {               # at least the path worked
        is $e->message, "No such application fee: $id",
          'refunded application fee';
    }
};

subtest Account => sub {
    plan tests => 1;
    my $account = $stripe->account;
    ok $account, 'retrieved account details';
};

subtest Balance => sub {
    plan tests => 3;
    my $balance = $stripe->balance('retrieve');
    ok $balance, 'retrieved balance';
    my $history = $stripe->balance('history');
    ok $history, 'retrieved balance history';

    # this will suffice to test our paths
    eval {
        $balance = $stripe->balance( transaction => $charge );
        ok $balance, 'retrieved a balance transaction';
    };
    if ( my $e = $@ ) {
        is $e->message, "No such balancetransaction: $charge",
          'retrieved a balance transaction';
    }
};

subtest Events => sub {
    plan tests => 2;
    my $events = $stripe->events( list => { created => { gt => $time } } );
    ok scalar @{ $events->data }, 'listed events';
    my $event = $events->data->[0];
    my $id    = $event->id;
    $event = $stripe->events( retrieve => $id );
    is $event->id, $id, 'retrieved an event';
};

subtest 'Various Exports' => sub {
    plan tests => 4;
    my $do = data_object( { foo => 'bar' } );
    is $do->foo, 'bar', 'created a data object';
    like ref(true),  qr/JSON/, 'exported true';
    like ref(false), qr/JSON/, 'exported false';
    eval { null };
    ok !$@, 'exported null';
};

done_testing;

# clean up
END {
    eval { $stripe->plans( delete => $plan )       if $plan };
    eval { $stripe->plans( delete => $spare_plan ) if $spare_plan };
    eval {
        $stripe->subscriptions(
            cancel => {
                id       => $subscription,
                customer => $customer,
            }
        ) if $subscription;
    };
    eval { $stripe->customers( delete => $customer ) if $customer };
    eval { $stripe->coupons( delete => $coupon ) if $coupon };
    eval { $stripe->recipients( delete => $recipient ) if $recipient };
}

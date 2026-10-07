import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/core/unsigned_int.dart';
import 'package:jmap_dart_client/jmap/core/user_name.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/domain/exceptions/spam_report_exception.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/domain/repository/spam_report_repository.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/domain/state/get_spam_mailbox_cached_state.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/domain/usecases/get_spam_mailbox_cached_interactor.dart';

import 'get_spam_mailbox_cached_interactor_test.mocks.dart';

@GenerateNiceMocks([MockSpec<SpamReportRepository>()])
void main() {
  final accountId = AccountId(Id('account-1'));
  final userName = UserName('user@example.com');

  late MockSpamReportRepository spamReportRepository;
  late GetSpamMailboxCachedInteractor interactor;

  setUp(() {
    spamReportRepository = MockSpamReportRepository();
    interactor = GetSpamMailboxCachedInteractor(spamReportRepository);
  });

  Mailbox makeSpamMailbox({required int unreadCount}) => Mailbox(
        id: MailboxId(Id('spam-id')),
        unreadEmails:
            unreadCount > 0 ? UnreadEmails(UnsignedInt(unreadCount)) : null,
      );

  int msAgo(int hours) =>
      DateTime.now().subtract(Duration(hours: hours)).millisecondsSinceEpoch;

  // Predicate matchers for Left states — EquatableMixin compares exception by value,
  // so isA<>() inside Left(...) breaks equality. Use predicate instead.
  Matcher leftWithException<E>() => predicate<Either<Failure, Success>>(
        (either) => either.fold(
          (f) => f is GetSpamMailboxCachedFailure && f.exception is E,
          (_) => false,
        ),
        'Left(GetSpamMailboxCachedFailure($E))',
      );

  group('GetSpamMailboxCachedInteractor', () {
    group('first-time user (no stored dismiss timestamp)', () {
      test('shows banner when there are unread spam emails', () {
        final spamMailbox = makeSpamMailbox(unreadCount: 5);
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenAnswer((_) async => 0);
        when(spamReportRepository.getSpamMailboxCached(accountId, userName))
            .thenAnswer((_) async => spamMailbox);

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            Right(GetSpamMailboxCachedSuccess(spamMailbox)),
          ]),
        );
      });

      test('does not show banner when spam folder has no unread emails', () {
        final spamMailbox = makeSpamMailbox(unreadCount: 0);
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenAnswer((_) async => 0);
        when(spamReportRepository.getSpamMailboxCached(accountId, userName))
            .thenAnswer((_) async => spamMailbox);

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            leftWithException<NoUnreadSpamEmailsException>(),
          ]),
        );
      });
    });

    group('cooldown active (dismissed less than 24h ago)', () {
      test('does not show banner when dismissed 13 hours ago', () {
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenAnswer((_) async => msAgo(13));

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            leftWithException<SpamDismissCooldownActiveException>(),
          ]),
        );
      });

      test('does not show banner when dismissed 1 hour ago', () {
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenAnswer((_) async => msAgo(1));

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            leftWithException<SpamDismissCooldownActiveException>(),
          ]),
        );
      });
    });

    group('cooldown expired (dismissed 24h ago)', () {
      test('shows banner when dismissed exactly 24 hours ago and unread > 0',
          () {
        final spamMailbox = makeSpamMailbox(unreadCount: 3);
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenAnswer((_) async => msAgo(24));
        when(spamReportRepository.getSpamMailboxCached(accountId, userName))
            .thenAnswer((_) async => spamMailbox);

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            Right(GetSpamMailboxCachedSuccess(spamMailbox)),
          ]),
        );
      });

      test('shows banner when dismissed 25 hours ago and unread > 0', () {
        final spamMailbox = makeSpamMailbox(unreadCount: 3);
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenAnswer((_) async => msAgo(25));
        when(spamReportRepository.getSpamMailboxCached(accountId, userName))
            .thenAnswer((_) async => spamMailbox);

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            Right(GetSpamMailboxCachedSuccess(spamMailbox)),
          ]),
        );
      });

      test('does not show banner when dismissed 25 hours ago but unread = 0',
          () {
        final spamMailbox = makeSpamMailbox(unreadCount: 0);
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenAnswer((_) async => msAgo(25));
        when(spamReportRepository.getSpamMailboxCached(accountId, userName))
            .thenAnswer((_) async => spamMailbox);

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            leftWithException<NoUnreadSpamEmailsException>(),
          ]),
        );
      });
    });

    group('clock-skew (future timestamp)', () {
      test(
          'does not show banner when stored timestamp is 12 hours in the future (< 1 day clock skew)',
          () {
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenAnswer((_) async => msAgo(-12));

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            leftWithException<SpamDismissCooldownActiveException>(),
          ]),
        );
      });

      test(
          'shows banner when stored timestamp is 25 hours in the future (>= 1 day clock skew, likely clock reset)',
          () {
        final spamMailbox = makeSpamMailbox(unreadCount: 3);
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenAnswer((_) async => msAgo(-25));
        when(spamReportRepository.getSpamMailboxCached(accountId, userName))
            .thenAnswer((_) async => spamMailbox);

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            Right(GetSpamMailboxCachedSuccess(spamMailbox)),
          ]),
        );
      });
    });

    group('error handling', () {
      test('wraps repository exception in GetSpamMailboxCachedFailure', () {
        final exception = Exception('cache error');
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenThrow(exception);

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            Left(GetSpamMailboxCachedFailure(exception)),
          ]),
        );
      });

      test(
          'wraps getSpamMailboxCached exception in GetSpamMailboxCachedFailure',
          () {
        final exception = Exception('mailbox not found');
        when(spamReportRepository
                .getLastTimeDismissedSpamReportedMilliseconds())
            .thenAnswer((_) async => 0);
        when(spamReportRepository.getSpamMailboxCached(accountId, userName))
            .thenThrow(exception);

        expect(
          interactor.execute(accountId, userName),
          emitsInOrder([
            Right(GetSpamMailboxCachedLoading()),
            Left(GetSpamMailboxCachedFailure(exception)),
          ]),
        );
      });
    });
  });
}

import 'dart:convert';

import 'package:fdl_server/src/builders/transaction.dart';
import 'package:fdl_server/src/interfaces/controller.dart';
import 'package:fdl_server/src/middlewares/auth_check.dart';
import 'package:fdl_server/src/middlewares/post_args_check.dart';
import 'package:fdl_server/src/shared/builders.dart';
import 'package:fdl_server/src/shared/instances.dart';
import 'package:fdl_server/src/utils/get_auth_details.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Provide economy routes
class EconomyController extends IController {
  @override
  Router get router {
    final router = Router();

    router.post(
      '/<id>/pay',
      Pipeline()
          .addMiddleware(AuthCheckMiddleware().middleware())
          .addMiddleware(
              PostArgsMiddleware(requiredArgs: ['amount']).middleware())
          .addHandler(pay),
    );

    return router;
  }

  /// Process payment.
  Future<Response> pay(Request request) async {
    final args = request.context['body'] as Map<String, dynamic>;

    // Fetch args.
    final payeeName = request.params['id']!;
    final amount = args['amount'] as int;
    final comment = args['comment'] as String?;
    final payerId = (await getAuthDetails(request))['user_id']! as String;

    // Get required database collections.
    final passports = database.collection('passports');
    final economy = database.collection('economy');
    final paymentHistory = database.collection('payment_history');

    // Find payee passport by nickname.
    final payeePassport = await passports.findOne(
      where.eq('nickname', payeeName),
    );
    if (payeePassport == null) {
      return Response.notFound(
        jsonEncode(Builders.userNotFoundError.build()),
      );
    }
    final payeeId = payeePassport['_id'];

    // Find payer and payee economy states by its ids.
    final payerEconomy = (await economy.findOne(where.eq('_id', payerId)))!;
    final payeeEconomy = (await economy.findOne(where.eq('_id', payeeId)))!;

    // Check for payer funds.
    if (payerEconomy['balance'] < amount) {
      return Response.forbidden(
        jsonEncode(Builders.insufficientFundsError.build()),
      );
    }

    // Update payee balance.
    await economy.updateOne(
      where.eq('_id', payeeId),
      modify.set('balance', payeeEconomy['balance'] + amount),
    );

    // Update payer balance.
    await economy.updateOne(
      where.eq('_id', payerId),
      modify.set('balance', payerEconomy['balance'] - amount),
    );

    // Add transaction to history.
    final transaction = TransactionBuilder(
      payer: payerId,
      payee: payeeId,
      amount: amount,
      comment: comment,
      at: DateTime.now(),
    ).build();

    await paymentHistory.insert(transaction);

    // i dont know why it puts values :v
    transaction.remove('_id');

    return Response.ok(jsonEncode(transaction));
  }
}

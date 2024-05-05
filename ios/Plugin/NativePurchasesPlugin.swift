import Foundation
import Capacitor
import StoreKit

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(NativePurchasesPlugin)
public class NativePurchasesPlugin: CAPPlugin {

    private let PLUGIN_VERSION = "0.0.25"

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.PLUGIN_VERSION])
    }

    @objc func isBillingSupported(_ call: CAPPluginCall) {
        if #available(iOS 15, *) {
            call.resolve([
                "isBillingSupported": true
            ])
        } else {
            call.resolve([
                "isBillingSupported": false
            ])
        }
    }

    @objc func purchaseProduct(_ call: CAPPluginCall) {
        if #available(iOS 15, *) {
            print("purchaseProduct")
            let productIdentifier = call.getString("productIdentifier", "")
            let quantity = call.getInt("quantity", 1)
            if productIdentifier.isEmpty {
                call.reject("productIdentifier is Empty, give an id")
                return
            }

            Task {
                do {
                    let products = try await Product.products(for: [productIdentifier])
                    let product = products[0]
                    var purchaseOptions = Set<Product.PurchaseOption>()
                    purchaseOptions.insert(Product.PurchaseOption.quantity(quantity))
                    let result = try await product.purchase(options: purchaseOptions)
                    print("purchaseProduct result \(result)")
                    switch result {
                    case let .success(.verified(transaction)):
                        // Successful purhcase
                        await transaction.finish()
						let transactionStr = MyTransaction(
							environment: transaction.environment,
							storefront: transaction.storefront,
							originalID: transaction.originalID,
							originalPurchaseDate: transaction.originalPurchaseDate,
							id: transaction.id,
							webOrderLineItemID: transaction.webOrderLineItemID,
							appBundleID: transaction.appBundleID,
							productID: transaction.productID,
							productType: transaction.productType,
							subscriptionGroupID:  transaction.subscriptionGroupID,
							purchaseDate:  transaction.purchaseDate,
							expirationDate:  transaction.expirationDate, // 1 week later
							isUpgraded: transaction.isUpgraded,
							ownershipType: transaction.ownershipType,
							purchasedQuantity: transaction.purchasedQuantity,
							subscriptionStatus:transaction.subscriptionStatus,
							reason: transaction.reason,
							offer: transaction.offer,
							revocationDate: transaction.revocationDate,
							revocationReason: transaction.revocationReason,
							appAccountToken: transaction.appAccountToken
						)
                        call.resolve(["transaction": transactionStr])
                    case let .success(.unverified(_, error)):
                        // Successful purchase but transaction/receipt can't be verified
                        // Could be a jailbroken phone
                        call.reject(error.localizedDescription)
                    case .pending:
                        // Transaction waiting on SCA (Strong Customer Authentication) or
                        // approval from Ask to Buy
                        call.reject("Transaction pending")
                    case .userCancelled:
                        // ^^^
                        call.reject("User cancelled")
                    @unknown default:
                        call.reject("Unknown error")
                    }
                } catch {
                    print(error)
                    call.reject(error.localizedDescription)
                }
            }
        } else {
            print("Not implemented under ios 15")
            call.reject("Not implemented under ios 15")
        }
    }

    @objc func restorePurchases(_ call: CAPPluginCall) {
        if #available(iOS 15.0, *) {
            print("restorePurchases")
            DispatchQueue.global().async {
                Task {
                    do {
                        try await AppStore.sync()
                        // make finish() calls for all transactions and consume all consumables
                        for transaction in SKPaymentQueue.default().transactions {
                            SKPaymentQueue.default().finishTransaction(transaction)
                        }
                        call.resolve()
                    } catch {
                        call.reject(error.localizedDescription)
                    }
                }
            }
        } else {
            print("Not implemented under ios 15")
            call.reject("Not implemented under ios 15")
        }
    }

    @objc func getProducts(_ call: CAPPluginCall) {
        if #available(iOS 15.0, *) {
            let productIdentifiers = call.getArray("productIdentifiers", String.self) ?? []
            DispatchQueue.global().async {
                Task {
                    do {
                        let products = try await Product.products(for: productIdentifiers)
                        let productsJson: [[String: Any]] = products.map { $0.dictionary }
                        call.resolve([
                            "products": productsJson
                        ])
                    } catch {
                        print(error)
                        call.reject(error.localizedDescription)
                    }
                }
            }
        } else {
            print("Not implemented under ios 15")
            call.reject("Not implemented under ios 15")
        }
    }


	// 定义Transaction对象的属性
	struct MyTransaction {
		let environment: String // AppStore.Environment的字符串表示
		let storefront: String // Storefront的字符串表示
		let originalID: UInt64 // 原始交易标识符
		let originalPurchaseDate: String // 原始购买日期的字符串表示
		let id: UInt64 // 交易的唯一标识符
		let webOrderLineItemID: String? // 订阅购买事件的唯一ID
		let appBundleID: String // 应用的bundle标识符
		let productID: String // 应用内购买的产品标识符
		let productType: String // 应用内购买的产品类型
		let subscriptionGroupID: String? // 订阅组的标识符
		let purchaseDate: String // 购买日期的字符串表示
		let expirationDate: String? // 订阅的过期或续订日期的字符串表示
		let isUpgraded: Bool // 是否升级到另一个订阅
		let ownershipType: String // 交易的所有类型
		let purchasedQuantity: Int // 购买的消耗品数量
		let subscriptionStatus: String? // 订阅组的状态信息
		let reason: String // 购买交易的原因
		let offer: [String: Any]? // 订阅优惠信息
		let revocationDate: String? // 交易被撤销或退款的日期
		let revocationReason: String? // 交易被撤销或退款的原因
		let appAccountToken: String? // 关联交易的用户UUID

		// 将Transaction对象转换为JSON Data
		func toJSONData() throws -> Data {
			let dateFormatter = DateFormatter()
			dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
			
			let transactionDict: [String: Any] = [
				"environment": environment,
				"storefront": storefront,
				"originalID": originalID,
				"originalPurchaseDate": dateFormatter.string(from: originalPurchaseDate as Date),
				"id": id,
				"webOrderLineItemID": webOrderLineItemID,
				"appBundleID": appBundleID,
				"productID": productID,
				"productType": productType,
				"subscriptionGroupID": subscriptionGroupID,
				"purchaseDate": dateFormatter.string(from: purchaseDate as Date),
				"expirationDate": expirationDate.flatMap { dateFormatter.string(from: $0 as Date) },
				"isUpgraded": isUpgraded,
				"ownershipType": ownershipType,
				"purchasedQuantity": purchasedQuantity,
				"subscriptionStatus": subscriptionStatus,
				"reason": reason,
				"offer": offer,
				"revocationDate": revocationDate.flatMap { dateFormatter.string(from: $0 as Date) },
				"revocationReason": revocationReason,
				"appAccountToken": appAccountToken
			]
			
			return try JSONSerialization.data(withJSONObject: transactionDict, options: [])
		}
	}
}

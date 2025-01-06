# Configuration
- **DBMS:** MySQL/MariaDB 11
- **Engine:** InnoDB

# Tables:
- **addresses:** customer saved addresses for autofilling payment and shipping details
- **billing_details:** payment data
- **attributes:** product attributes (size, color, etc.)
- **cart:** customer carts (one per order)
- **cart_item:** item in cart
- **categories:** product categories (using *Nested Set*)
- **customers:** ecommerce shop' customers
- **invoices:** customer invoices (available when order is paid)
- **invoice_lines:** individual bought product information (tax, net price)
- **login_history:** users and customers login timestamps (NOT FINISHED)
- **orders:** customer orders
- **payment_providers**
- **permissions:** permission that provides access to specific actions in DB (for *users*)
- **products:** information about clothes (two types: *configurable* and *simple*)
- **roles:** permission grouped in roles that can be assigned to users
- **shipping_details:** shipment data
- **shipping_providers**
- **stock_events:** stock level history logs (using *Event Sourcing*)
- **users:** in other words: ecommerce shop' workers
- **vendors:** product manufacturers
  
# Procedures:
- **add_order** add new order with status='placed'
- **add_product_to_cart:** add new product or modify the existing product's quantity in cart
- **add_billing_details:** add billing details for customer who doesn't have saved address
- **add_shipping_details:** add shipping details for customer who doesn't have saved address
- **add_customer:** add new customer (could return error if function that generate random email create duplicate)
- **add_user:** similar to add_customer but create new user
- **delete_product_from_cart** 'delete' product in cart assigned to given customer ID in parameter (updating deleted_at column)
- **pay_order:** generate transaction ID for selected payment provider, create invoice and invoice lines, update order status to 'paid'
- **prepare_order_shipment:** generate tracking url for customer and change order status to 'ready_to_ship'
- **ship_order:** change order status to 'shipped'
- **return_order:** if order is 'shipped', add stock event 'returned' with the quantity of returned products
- **cancel_order:** if order has status other than 'shipped', add stock event 'order_cancelled' with the quantity of cancelled products
- 

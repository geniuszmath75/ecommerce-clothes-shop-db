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

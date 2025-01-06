-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: db.it.pk.edu.pl
-- Generation Time: Sty 06, 2025 at 01:55 PM
-- Wersja serwera: 11.6.1-MariaDB
-- Wersja PHP: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `projekt_gumulak_judka`
--
DROP DATABASE IF EXISTS `projekt_gumulak_judka`;
CREATE DATABASE IF NOT EXISTS `projekt_gumulak_judka` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE `projekt_gumulak_judka`;

DELIMITER $$
--
-- Procedury
--
DROP PROCEDURE IF EXISTS `add_billing_details`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `add_billing_details` (IN `id_customer` BIGINT(20), IN `id_provider` BIGINT(20), IN `address_title` VARCHAR(255), IN `f_name` VARCHAR(100), IN `l_name` VARCHAR(100), IN `p_email` VARCHAR(255), IN `p_phone_number` VARCHAR(20), OUT `id_billing` BIGINT(20) UNSIGNED)  SQL SECURITY INVOKER COMMENT 'Tworzy nowy wpis w szczegółach płatności' BEGIN
	DECLARE id_address BIGINT;

	IF address_title IS NOT NULL AND LENGTH(address_title) > 0 THEN
    	SELECT address_id INTO id_address FROM addresses WHERE customer_id=id_customer AND TRIM(title)=address_title;
        SELECT a.phone_number INTO p_phone_number FROM addresses a WHERE a.address_id=id_address;
        
        SELECT c.first_name, c.last_name, c.email INTO f_name, l_name, p_email FROM customers c WHERE c.customer_id=id_customer;
    END IF;
    
    SET id_billing = check_billing_details(id_provider, f_name, l_name, p_email, p_phone_number);
    
    IF id_billing = 0 THEN
    	INSERT INTO billing_details(payment_provider_id, first_name, last_name, email, phone_number) VALUES(id_provider, f_name, l_name, p_email, p_phone_number);
        SET id_billing = LAST_INSERT_ID();
   	END IF;
END$$

DROP PROCEDURE IF EXISTS `add_customer`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `add_customer` (IN `f_name` VARCHAR(100), IN `l_name` VARCHAR(100))  SQL SECURITY INVOKER BEGIN
	SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    
    SET @customer_email = '';
    SET @customer_pass = '';
    SET @customer_dob = '1970-01-02';
    
   	SET @customer_email = generate_email(f_name, l_name);
    
   	IF EXISTS (SELECT 1 FROM customers WHERE email=@customer_email)
        THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = "Klient z podanym emailem już istnieje. Spróbuj jeszcze raz.";
        ELSE
        	SET @customer_pass = generate_random_hashed_password();
            SET @customer_dob = generate_random_date('1971-01-02', '2014-01-01');
    		INSERT INTO customers(customer_id, first_name, last_name, date_of_birth, email, password) VALUES(NULL, f_name, l_name, @customer_dob, @customer_email, @customer_pass);
    		COMMIT;
    END IF;
END$$

DROP PROCEDURE IF EXISTS `add_invoice_lines`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `add_invoice_lines` (IN `id_invoice` BIGINT(20) UNSIGNED, IN `id_order` BIGINT(20) UNSIGNED)  SQL SECURITY INVOKER BEGIN
	DECLARE finished INT DEFAULT FALSE;
    DECLARE id_product BIGINT;
    DECLARE product_quantity INT;
    DECLARE unit_net_price INT;
    DECLARE tax INT;
    
    DECLARE cart_items_cursor CURSOR FOR SELECT product_id, quantity
    	FROM cart_item WHERE cart_id = (
            SELECT cart_id FROM cart WHERE cart_id = (
            	SELECT cart_id FROM orders WHERE order_id = id_order
            )
        );
        
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET finished = TRUE;
    OPEN cart_items_cursor;
    
    items_loop: LOOP
    	FETCH cart_items_cursor INTO id_product, product_quantity;
        
        IF finished = TRUE THEN
        	LEAVE items_loop;
        END IF;
        
        SELECT net_price INTO unit_net_price FROM products WHERE product_id = id_product;
        SELECT IFNULL((SELECT tax_class FROM products WHERE product_id = (
        	SELECT parent_id FROM products WHERE product_id = id_product
        )), (SELECT tax_class FROM products WHERE product_id = id_product)) INTO tax;
        
        INSERT INTO invoice_lines(invoice_id, product_id, quantity, unit_cost_net, tax_class, line_total_net) VALUES(id_invoice, id_product, product_quantity, unit_net_price, tax, (product_quantity * unit_net_price));
        
    END LOOP;
    
    CLOSE cart_items_cursor;
END$$

DROP PROCEDURE IF EXISTS `add_login_log`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `add_login_log` (IN `user_type` ENUM('user','customer'), IN `id_user` BIGINT(20) UNSIGNED, IN `action_type` ENUM('add_to_cart','add_order'))  SQL SECURITY INVOKER BEGIN

	DECLARE ip VARCHAR(15);
    DECLARE ug VARCHAR(255);
    DECLARE user_logged INT DEFAULT 0;
    DECLARE login_time TIMESTAMP;
    DECLARE session_time INT DEFAULT 30 * 60; -- w sekundach
    DECLARE mm TINYINT DEFAULT 0;
    DECLARE ss TINYINT DEFAULT 0;
	
    -- Ustawiamy losowe IP
    SET ip = generate_random_ip();
    
    -- Ustawiamy losowy user_agent
    SET ug = generate_random_user_agent();

	-- Jeśli użytkownik dodał produkt do koszyka to przyjmujemy,
    -- że jego sesja trwała od 10 do 30 min
	IF action_type='add_to_cart' THEN
    	SET mm = FLOOR(RAND() * 20) + 10;
        SET ss = FLOOR(RAND() * 60);
    	SET session_time = mm * 60 + ss;
    END IF;
    
    -- Jeśli użytkownik dodał zamówienie to przyjmujemy,
    -- że jego sesja trwała od 30 do 60 min 
  	IF action_type='add_order' THEN
    	SET mm = FLOOR(RAND() * 30) + 30;
        SET ss = FLOOR(RAND() * 60);
    	SET session_time = mm * 60 + ss;
    END IF;
    
    -- Obliczamy datę logowania
    SET login_time = DATE_SUB(NOW(), INTERVAL session_time SECOND);
    
    -- Jeśli użytkownik jest użytkownikiem bazy - customer_id=NULL
    IF user_type='user' THEN
    	SELECT 1 INTO user_logged FROM login_history WHERE user_id=id_user AND TIMESTAMPDIFF(MINUTE, created_at, NOW()) < 30 ORDER BY created_at DESC LIMIT 1;
        IF user_logged=0 THEN
    		INSERT INTO login_history(user_id, ip_address, user_agent, created_at) VALUES(id_user, ip, ug, login_time);
        END IF;
    END IF;
    
    -- Jeśli użytkownik jest klientem sklepu - user_id=NULL
    IF user_type='customer' THEN
    	SELECT 1 INTO user_logged FROM login_history WHERE customer_id=id_user AND TIMESTAMPDIFF(MINUTE, created_at, NOW()) < 30 ORDER BY created_at DESC LIMIT 1;
        IF user_logged=0 THEN
    		INSERT INTO login_history(customer_id, ip_address, user_agent, created_at) VALUES(id_user, ip, ug, login_time);
        END IF;
    END IF;
END$$

DROP PROCEDURE IF EXISTS `add_order`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `add_order` (IN `id_customer` BIGINT(20) UNSIGNED, IN `id_billing_provider` BIGINT(20) UNSIGNED, IN `id_shipping_provider` BIGINT(20) UNSIGNED, IN `address_title` VARCHAR(255))   BEGIN
    DECLARE error_message TEXT;
    DECLARE id_cart INT;
    DECLARE id_product BIGINT;
    DECLARE number_of_items INT DEFAULT 0;
    DECLARE latest_shipping_details_id BIGINT;
    DECLARE latest_billing_details_id BIGINT;
    DECLARE existing_address_id BIGINT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
        	GET DIAGNOSTICS CONDITION 1
            	error_message=MESSAGE_TEXT;
            ROLLBACK;
        	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
        END;

	SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    
    -- Szukanie najnowszego aktywnego koszyka
	SELECT cart_id, item_count INTO id_cart, number_of_items FROM cart WHERE customer_id=id_customer AND active=1 ORDER BY updated_at DESC LIMIT 1;
    
    -- Sprawdzenie, czy są jakieś produkty w aktywnym koszyku
    IF id_cart IS NULL OR number_of_items=0 THEN
    	SET error_message = CONCAT("Aby złożyć zamówienie, dodaj przynajmniej jeden produkt do koszyka");
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
    END IF;
    
    -- Sprawdzenie, czy można kupić ilość produktu zapisaną w koszyku
    SELECT check_sellable_product_quantity(id_cart) INTO id_product;
    
    IF id_product > 0 THEN
    	SET error_message = CONCAT("Niewystarczająca ilość w magazynie produktu o ID: ", id_product, " do realizacji zamówienia. Zmień ilość produktu w koszyku.");
        ROLLBACK;
    	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = error_message;
    END IF;
    
    -- Sprawdzenie, czy dodano szczegóły wysyłki
    SELECT shipping_details_id INTO latest_shipping_details_id FROM shipping_details WHERE email=(
    	SELECT email FROM customers WHERE customer_id=id_customer
    ) AND shipper_provider_id=id_shipping_provider ORDER BY updated_at DESC LIMIT 1;
    
    -- Sprawdzenie, czy dodano szczegóły płatności
    SELECT billing_details_id INTO latest_billing_details_id FROM billing_details WHERE email =(
    	SELECT email FROM customers WHERE customer_id=id_customer
    ) AND payment_provider_id=id_billing_provider ORDER BY updated_at DESC LIMIT 1;
    
    -- Sprawdzenie, czy użytkownik posiada zapisany adres
    SELECT address_id INTO existing_address_id FROM addresses WHERE customer_id=id_customer AND TRIM(title)=address_title;
    
    IF existing_address_id IS NULL THEN
    	IF latest_billing_details_id IS NULL AND latest_shipping_details_id IS NULL THEN
            SET error_message = CONCAT("Użytkownik o ID ", id_customer, " nie ma zapisanego adresu
                                       o nazwie ", address_title, ". Wybierz inny adres lub dodaj nowy.");
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
    	ELSEIF latest_billing_details_id IS NULL THEN
    		SET error_message = "Dodaj szczegóły płatności";
        	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
    	ELSEIF latest_shipping_details_id IS NULL THEN
            SET error_message = "Dodaj szczegóły wysyłki";
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
        ELSE
        	UPDATE cart SET billing_details_id=latest_billing_details_id, shipping_details_id=latest_shipping_details_id, active = 0 WHERE cart_id=id_cart;
        	INSERT INTO orders(customer_id, cart_id, status) VALUES(id_customer, id_cart, 'placed');
            COMMIT;
    	END IF;
    ELSE
    	CALL add_billing_details(id_customer, id_billing_provider, address_title, NULL, NULL, NULL, NULL, @id_billing);
    
    	CALL add_shipping_details(id_customer, id_shipping_provider, address_title, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, @id_shipping);
        
        -- Dodanie danych o płatności oraz wysyłce
    	UPDATE cart SET billing_details_id=@id_billing, shipping_details_id=@id_shipping, active=0 WHERE cart_id=id_cart;
    
        -- Złożenie zamówienia
        INSERT INTO orders(customer_id, cart_id, status) VALUES(id_customer, id_cart, 'placed');
        COMMIT;
    END IF;
END$$

DROP PROCEDURE IF EXISTS `add_product_to_cart`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `add_product_to_cart` (IN `id_product` BIGINT UNSIGNED, IN `product_quantity` INT UNSIGNED, IN `id_customer` BIGINT UNSIGNED)   BEGIN
    DECLARE id_cart INT;
    DECLARE id_item INT;
    DECLARE cart_status INT;
    DECLARE error_message TEXT;
    
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
        	GET DIAGNOSTICS CONDITION 1
            	error_message=MESSAGE_TEXT;
            ROLLBACK;
        	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
        END;
    
    SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
    
    START TRANSACTION;
    SET @psq=0; -- product_stock_quantity
    
    -- Ilość danego produktu jaką można sprzedać
    SELECT SUM(diff) INTO @psq FROM stock_events WHERE product_id=id_product;
    
	-- Sprawdzenie, czy dany klient ma już przypisany koszyk 
    SELECT IFNULL((SELECT cart_id FROM cart WHERE customer_id=id_customer), NULL) AS cart_id INTO id_cart;

    -- Jeśli nie, tworzymy nowy koszyk i przypisujemy jego ID do id_cart.
    IF id_cart IS NULL THEN
        INSERT INTO cart(customer_id) VALUES(id_customer);
        SELECT cart_id INTO id_cart FROM cart WHERE customer_id=id_customer;
    END IF;

    -- Sprawdzenie, czy produkt, który chcemy dodać do koszyka znajduje się już w nim.
    SELECT IFNULL((SELECT item_id FROM cart_item WHERE cart_id=id_cart AND product_id=id_product), NULL) AS cart_item INTO id_item;

    -- Jeśli tak, aktualizujemy tylko ilość danego produktu.
    IF id_item IS NOT NULL THEN
    	-- Ilość danego produktu w koszyku, którego pozycję chcemy zaktualizować
        IF product_quantity <= @psq THEN
			UPDATE cart_item SET quantity=product_quantity WHERE item_id=id_item;
		ELSE
    		ROLLBACK;
    		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Brak produktu na magazynie.";
   		END IF;
    ELSE
		-- W przeciwnym wypadku, dodajemy nową pozycję do koszyka
    	IF product_quantity <= @psq THEN
			INSERT INTO cart_item(cart_id, product_id, quantity) VALUES(id_cart, id_product, product_quantity);
		ELSE
    		ROLLBACK;
    		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Brak produktu na magazynie.";
   		END IF;
    END IF;

    COMMIT;
	
END$$

DROP PROCEDURE IF EXISTS `add_role_permission`$$
$$

DROP PROCEDURE IF EXISTS `add_role_user`$$
$$

DROP PROCEDURE IF EXISTS `add_shipping_details`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `add_shipping_details` (IN `id_customer` BIGINT(20) UNSIGNED, IN `id_provider` BIGINT(20) UNSIGNED, IN `address_title` VARCHAR(255), IN `f_name` VARCHAR(100), IN `l_name` VARCHAR(100), IN `address_1` VARCHAR(100), IN `address_2` VARCHAR(100), IN `p_email` VARCHAR(255), IN `p_country` CHAR(2), IN `p_city` VARCHAR(255), IN `p_state` VARCHAR(255), IN `p_postal_code` VARCHAR(12), IN `p_phone_number` VARCHAR(20), OUT `id_shipping` BIGINT(20) UNSIGNED)   BEGIN
	DECLARE id_address BIGINT;

	IF address_title IS NOT NULL AND LENGTH(address_title) > 0 THEN
    	SELECT address_id INTO id_address FROM addresses WHERE customer_id=id_customer AND TRIM(title)=address_title;
        SELECT a.address_line_1, a.address_line_2, a.country, a.city, a.state, a.postal_code, a.phone_number INTO address_1, address_2, p_country, p_city, p_state, p_postal_code, p_phone_number FROM addresses a WHERE a.address_id=id_address;
        
        SELECT c.first_name, c.last_name, c.email INTO f_name, l_name, p_email FROM customers c WHERE c.customer_id=id_customer;
    END IF;
    
    SET id_shipping = check_shipping_details(id_provider, f_name, l_name, address_1, address_2, p_email, p_country, p_city, p_state, p_postal_code, p_phone_number);
    
    IF id_shipping = 0 THEN
    	IF LENGTH(address_2)=0 THEN
        	SET address_2 = NULL;
        END IF;
        
        IF LENGTH(p_state) = 0 THEN
        	SET p_state = NULL;
        END IF;
        
    	INSERT INTO shipping_details(shipper_provider_id, first_name, last_name, address_line_1, address_line_2, email, country, city, state, postal_code, phone_number) VALUES(id_provider, f_name, l_name, address_1, address_2, p_email, p_country, p_city, p_state, p_postal_code, p_phone_number);
        SET id_shipping = LAST_INSERT_ID();
   	END IF;
END$$

DROP PROCEDURE IF EXISTS `add_user`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `add_user` (IN `f_name` VARCHAR(100), IN `l_name` VARCHAR(100))  SQL SECURITY INVOKER BEGIN
	SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    
    SET @user_email = '';
    SET @user_pass = '';
    
   	SET @user_email = generate_email(f_name, l_name);
    
   	IF EXISTS (SELECT 1 FROM users WHERE email=@user_email)
        THEN
            ROLLBACK;
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = "Użytkownik z podanym emailem już istnieje. Spróbuj jeszcze raz.";
        ELSE
        	SET @user_pass = generate_random_hashed_password();
    		INSERT INTO users(users_id, first_name, last_name, email, password) VALUES(NULL, f_name, l_name, @user_email, @user_pass);
    		COMMIT;
    END IF;
END$$

DROP PROCEDURE IF EXISTS `cancel_order`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `cancel_order` (IN `id_order` BIGINT(20) UNSIGNED)   BEGIN
	DECLARE error_message TEXT;
    DECLARE id_cart BIGINT;
    DECLARE order_status ENUM('placed', 'paid', 'ready_to_ship', 'shipped');
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
        	GET DIAGNOSTICS CONDITION 1
            	error_message=MESSAGE_TEXT;
            ROLLBACK;
        	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
        END;

	SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
	
    SELECT status INTO order_status FROM orders WHERE order_id=id_order;
    
    IF order_status='shipped' THEN
    	ROLLBACK;
    	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Nie można anulować zamówienia, ponieważ zostało już wysłane.";
    END IF;
    
    SELECT cart_id INTO id_cart FROM cart WHERE cart_id = (
    	SELECT cart_id FROM orders WHERE order_id=id_order
    );
    
    -- Dodanie odpowiedniego zdarzenia
	CALL change_stock_level(id_order, id_cart, 'order_cancelled');

	COMMIT;
END$$

DROP PROCEDURE IF EXISTS `change_stock_level`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `change_stock_level` (IN `id_order` BIGINT(20) UNSIGNED, IN `id_cart` BIGINT(20) UNSIGNED, IN `event_name` ENUM('snapshot','stock_increased','stock_decreased','order_placed','order_dispatched','order_cancelled','returned'))  SQL SECURITY INVOKER BEGIN
	DECLARE done INT DEFAULT FALSE;
    DECLARE id_product BIGINT;
    DECLARE product_quantity INT;
    DECLARE product_cursor CURSOR FOR SELECT product_id, quantity FROM cart_item WHERE cart_id=id_cart AND deleted_at IS NULL;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done=TRUE;
    
    OPEN product_cursor;
    
    products_loop: LOOP
    	FETCH product_cursor INTO id_product, product_quantity;
        
        IF done=TRUE THEN
        	LEAVE products_loop;
        END IF;
        
        IF event_name IN('stock_decreased', 'order_placed', 'order_dispatched') THEN
        	SET product_quantity = -product_quantity;
        END IF;
        INSERT INTO stock_events(product_id, order_id, diff, event_type) VALUES(id_product, id_order, product_quantity, event_name);
        
    END LOOP;
END$$

DROP PROCEDURE IF EXISTS `delete_product_from_cart`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `delete_product_from_cart` (IN `id_customer` BIGINT(20) UNSIGNED, IN `id_product` BIGINT(20) UNSIGNED)   BEGIN
	DECLARE id_cart BIGINT;
    DECLARE error_message TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
        	GET DIAGNOSTICS CONDITION 1
            	error_message=MESSAGE_TEXT;
            ROLLBACK;
        	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
        END;

	SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    
    SELECT cart_id INTO id_cart FROM cart WHERE customer_id=id_customer AND active=1 AND item_count > 0 ORDER BY updated_at DESC LIMIT 1;
	
    -- Sprawdzenie, czy istnieje aktywny koszyk, który zawiera jakieś produkty
    IF id_cart IS NULL THEN
    	SET error_message = "Koszyk jest pusty";
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
    END IF;
    
    -- Jeśli tak - usuń wybrany produkt...
    IF EXISTS (SELECT item_id FROM cart_item WHERE cart_id=id_cart AND product_id=id_product) THEN
	    UPDATE cart_item SET deleted_at = CURRENT_TIMESTAMP() WHERE cart_id = id_cart AND product_id=id_product;
        COMMIT;
	-- ...o ile istnieje w koszyku
    ELSE
    	SET error_message = CONCAT("Brak produktu o ID: ", id_product, " w koszyku.");
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
    END IF;
END$$

DROP PROCEDURE IF EXISTS `increase_quantity`$$
$$

DROP PROCEDURE IF EXISTS `pay_order`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `pay_order` (IN `id_order` BIGINT(20) UNSIGNED)   BEGIN
	
    DECLARE transaction_id VARCHAR(50);
    DECLARE total_net_value INT;
    DECLARE total_gross_value INT;
    DECLARE error_message TEXT;
    DECLARE id_invoice BIGINT;
    DECLARE id_cart BIGINT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    	BEGIN
        	GET DIAGNOSTICS CONDITION 1
            	error_message = MESSAGE_TEXT;
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = error_message;
        END;
    
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    
    START TRANSACTION;
    
    -- Wygenerowanie ID transakcji
    SET transaction_id = generate_transaction_id(id_order);
    
    -- Obliczenie całkowitej wartości netto zamówienia 
    SET total_net_value = calculate_cart_total_value(id_order, FALSE);
    
    -- Obliczenie całkowitej wartości brutto zamówienia
    SET total_gross_value = calculate_cart_total_value(id_order, TRUE);
    
    -- Utworzenie faktury dla danego zamówienia
    INSERT INTO invoices(order_id, external_transaction_id, total_net, total_gross) VALUES(id_order, transaction_id, total_net_value, total_gross_value);
    
    -- Pobranie ID faktury
    SET id_invoice = LAST_INSERT_ID();
    
    -- Utworzenie pozycji na fakturze dla każdego towaru
    CALL add_invoice_lines(id_invoice, id_order);
    
    -- Aktualizacja statusu zamówienia
    UPDATE orders SET status='paid' WHERE order_id=id_order;
    
    COMMIT;
    
END$$

DROP PROCEDURE IF EXISTS `prepare_order_shipment`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `prepare_order_shipment` (IN `id_order` BIGINT(20) UNSIGNED)   BEGIN

	DECLARE error_message TEXT;
    DECLARE id_details BIGINT;
    DECLARE shipment_url VARCHAR(255);
    DECLARE order_status ENUM("placed", "paid", "ready_to_ship", "shipped");
	
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
    	BEGIN
        	GET DIAGNOSTICS CONDITION 1
            	error_message = MESSAGE_TEXT;
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = error_message;
        END;
    
	START TRANSACTION;
    
    SELECT status INTO order_status FROM orders WHERE order_id = id_order;
    
    IF order_status = 'placed' THEN
    	ROLLBACK;
    	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Zamówienie nie zostało opłacone.";
    ELSEIF order_status IN('ready_to_ship', 'shipped') THEN
    	ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Zamówienie zostało wysłane lub czeka na wysłanie.";
    ELSE
    	SELECT shipping_details_id INTO id_details FROM cart WHERE cart_id = (
    		SELECT cart_id FROM orders WHERE order_id = id_order
    	);
    
        -- Wygenerowanie linku do śledzenia przesyłki
        SET shipment_url = generate_tracking_url(id_details);

        -- Aktualizacja zamówienia na gotowe do wysłania
        UPDATE orders SET status='ready_to_ship', tracking_url=shipment_url WHERE order_id = id_order;

        COMMIT;
    END IF;
END$$

DROP PROCEDURE IF EXISTS `return_order`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `return_order` (IN `id_order` BIGINT(20) UNSIGNED)   BEGIN

	DECLARE error_message TEXT;
    DECLARE id_cart BIGINT;
    DECLARE order_status ENUM('placed', 'paid', 'ready_to_ship', 'shipped');
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
        	GET DIAGNOSTICS CONDITION 1
            	error_message=MESSAGE_TEXT;
            ROLLBACK;
        	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=error_message;
        END;

	SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    
    SELECT status INTO order_status FROM orders WHERE order_id=id_order;
    
    IF order_status IN('placed', 'paid', 'ready_to_ship') THEN
    	ROLLBACK;
    	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Nie można zwrócić zamówienia, ponieważ nie zostało jeszcze wysłane.";
    END IF;
    
    SELECT cart_id INTO id_cart FROM cart WHERE cart_id = (
    	SELECT cart_id FROM orders WHERE order_id=id_order
    );
    
    -- Zwrócenie towaru do magazynu
    CALL change_stock_level(id_order, id_cart, 'returned');
    
    COMMIT;

END$$

DROP PROCEDURE IF EXISTS `ship_order`$$
CREATE DEFINER=`judka_damian`@`%` PROCEDURE `ship_order` (IN `id_order` BIGINT(20) UNSIGNED)   BEGIN

	DECLARE order_status ENUM('placed', 'paid', 'ready_to_ship', 'shipped');
	DECLARE error_message TEXT;

	DECLARE EXIT HANDLER FOR SQLEXCEPTION
    	BEGIN
        	GET DIAGNOSTICS CONDITION 1
            	error_message = MESSAGE_TEXT;
            ROLLBACK;
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = error_message;
        END;
    
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

	START TRANSACTION;
    
    SELECT status INTO order_status FROM orders WHERE order_id=id_order;
    
    IF order_status='placed' THEN
    	ROLLBACK;
    	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Zamówienie nie zostało opłacone!";
    ELSEIF order_status='paid' THEN
    	ROLLBACK;
    	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Zamówienie nie zostało przygotowane do wysyłki!";
    ELSEIF order_status='shipped' THEN
    	ROLLBACK;
    	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Zamówienie zostało już wysłane.";
    ELSE    
    	-- Zaktualizuj status zamówienia na wysłane
    	UPDATE orders SET status='shipped' WHERE order_id=id_order;
    	COMMIT;
   	END IF;
END$$

--
-- Functions
--
DROP FUNCTION IF EXISTS `calculate_cart_total_value`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `calculate_cart_total_value` (`id_order` BIGINT(20) UNSIGNED, `is_gross` BOOLEAN) RETURNS INT(10) UNSIGNED SQL SECURITY INVOKER BEGIN
	DECLARE finished INT DEFAULT FALSE;
    DECLARE id_product BIGINT;
    DECLARE product_quantity INT;
    DECLARE unit_net_price INT;
    DECLARE total_price INT DEFAULT 0;
    DECLARE tax DECIMAL(3, 2) DEFAULT 0;
    
    DECLARE products_cursor CURSOR FOR SELECT product_id, quantity FROM cart_item
    WHERE cart_id = (
    	SELECT cart_id FROM orders
    	WHERE order_id = id_order
	);    
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET finished = TRUE;
    
    OPEN products_cursor;
    
    products_loop: LOOP
    	FETCH products_cursor INTO id_product, product_quantity;
    
    	IF finished = TRUE THEN
        	LEAVE products_loop;
        END IF;
        
        SELECT net_price INTO unit_net_price FROM products WHERE product_id = id_product;
        
        IF is_gross = TRUE THEN
        	SELECT IFNULL((SELECT (1 + (tax_class / 100.0)) FROM products WHERE product_id = (
            	SELECT parent_id FROM products WHERE product_id = id_product
            )), (SELECT (1 + (tax_class / 100.0)) FROM products WHERE product_id = id_product)) INTO tax;
        	
            SET total_price = total_price + ( unit_net_price * tax * product_quantity );
        ELSE
        	SET total_price = total_price + ( unit_net_price * product_quantity );
        END IF;
    END LOOP;
    
    RETURN total_price;
END$$

DROP FUNCTION IF EXISTS `check_billing_details`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `check_billing_details` (`id_provider` BIGINT(20) UNSIGNED, `f_name` VARCHAR(100), `l_name` VARCHAR(100), `p_email` VARCHAR(255), `p_phone_number` VARCHAR(20)) RETURNS BIGINT(20) UNSIGNED  BEGIN
	DECLARE existing_id BIGINT DEFAULT 0;
    
	SELECT billing_details_id
    INTO existing_id
    FROM billing_details
    WHERE payment_provider_id = id_provider
      AND first_name = f_name
      AND last_name = l_name
      AND email = p_email
      AND phone_number = p_phone_number;
      
   	RETURN existing_id;
END$$

DROP FUNCTION IF EXISTS `check_sellable_product_quantity`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `check_sellable_product_quantity` (`id_cart` BIGINT(20) UNSIGNED) RETURNS TINYINT(3) UNSIGNED  BEGIN
	DECLARE finished INT DEFAULT FALSE;
    DECLARE id_product BIGINT;
    DECLARE cart_quantity INT;
    DECLARE stock_quantity INT;
	DECLARE products_cursor CURSOR FOR SELECT product_id, quantity 
    FROM cart_item WHERE cart_id=id_cart;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET finished = TRUE;
    
    OPEN products_cursor;
    
    products_loop: LOOP
    	FETCH products_cursor INTO id_product, cart_quantity;
        
        IF finished = TRUE THEN
        	LEAVE products_loop;
        END IF;
        
        SELECT SUM(diff) INTO stock_quantity  FROM stock_events WHERE product_id = id_product;
        
        IF stock_quantity < cart_quantity THEN
        	RETURN id_product;
        END IF;
    END LOOP;
    
    CLOSE products_cursor;
    
    RETURN 0;
END$$

DROP FUNCTION IF EXISTS `check_shipping_details`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `check_shipping_details` (`id_provider` BIGINT(20) UNSIGNED, `f_name` VARCHAR(100), `l_name` VARCHAR(100), `address_1` VARCHAR(100), `address_2` VARCHAR(100), `p_email` VARCHAR(255), `p_country` CHAR(2), `p_city` VARCHAR(255), `p_state` VARCHAR(255), `p_postal_code` VARCHAR(12), `p_phone_number` VARCHAR(20)) RETURNS BIGINT(20) UNSIGNED  BEGIN
	DECLARE existing_id BIGINT DEFAULT 0;
    
	SELECT shipping_details_id
    INTO existing_id
    FROM shipping_details
    WHERE shipper_provider_id = id_provider
      AND first_name = f_name
      AND last_name = l_name
      AND address_line_1 = address_1
      AND address_line_2 <=> address_2
      AND email = p_email
      AND country = p_country
      AND city = p_city
      AND state <=> p_state
      AND postal_code = p_postal_code
      AND phone_number = p_phone_number;
      
   	RETURN existing_id;
END$$

DROP FUNCTION IF EXISTS `generate_email`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `generate_email` (`first_name` VARCHAR(100), `last_name` VARCHAR(100)) RETURNS VARCHAR(255) CHARSET utf8mb4 COLLATE utf8mb4_general_ci  BEGIN
DECLARE random_number INT(5);
SET random_number = RAND() * 9999 + 1;

SET first_name = remove_diacritics(LOWER(first_name));
SET last_name = remove_diacritics(LOWER(last_name));

RETURN CONCAT(first_name, ".", last_name, random_number, '@gmail.com');
END$$

DROP FUNCTION IF EXISTS `generate_random_date`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `generate_random_date` (`start_date` DATE, `end_date` DATE) RETURNS DATE  BEGIN
	RETURN FROM_UNIXTIME(
        UNIX_TIMESTAMP(start_date) +
        FLOOR(RAND() * (UNIX_TIMESTAMP(end_date)- UNIX_TIMESTAMP(start_date))));
END$$

DROP FUNCTION IF EXISTS `generate_random_hashed_password`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `generate_random_hashed_password` () RETURNS VARCHAR(64) CHARSET utf8mb4 COLLATE utf8mb4_general_ci  BEGIN	
    DECLARE char_pool VARCHAR(64) DEFAULT "QWERTYUIOPASDFGHJKLZXCVBNM1234567890!@#$%^&*(),.?/<>";
    DECLARE pool_length INT DEFAULT LENGTH(char_pool);
    DECLARE loop_count INT DEFAULT 0;
    DECLARE random_string VARCHAR(64) DEFAULT '';
    DECLARE random_char CHAR(1);
    
    WHILE loop_count < 10
    DO
    	SET random_char = SUBSTRING(char_pool, FLOOR(1 + RAND() * pool_length), 1);
        SET random_string = CONCAT(random_string, random_char);
        SET loop_count = loop_count + 1;
    END WHILE;
    
    RETURN SHA2(random_string, 256);
END$$

DROP FUNCTION IF EXISTS `generate_random_ip`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `generate_random_ip` () RETURNS VARCHAR(15) CHARSET utf8mb4 COLLATE utf8mb4_general_ci  BEGIN

	DECLARE ip_address VARCHAR(15) DEFAULT '';
    
    FOR i IN 1..4 DO
    	SET ip_address = CONCAT(ip_address, (FLOOR(RAND() * 255) + 1));
        IF i <> 4 THEN
        	SET ip_address = CONCAT(ip_address, '.');
        END IF;
    END FOR;

	RETURN ip_address;
END$$

DROP FUNCTION IF EXISTS `generate_random_number`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `generate_random_number` (`start_number` INT(11) UNSIGNED, `end_number` INT(11) UNSIGNED) RETURNS INT(11)  BEGIN
RETURN FLOOR(RAND() * (end_number - start_number + 1)) + start_number;
END$$

DROP FUNCTION IF EXISTS `generate_random_user_agent`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `generate_random_user_agent` () RETURNS VARCHAR(255) CHARSET utf8mb4 COLLATE utf8mb4_general_ci  BEGIN
	DECLARE user_agent VARCHAR(255);
	DECLARE browser VARCHAR(50);
    DECLARE browser_version VARCHAR(20);
    DECLARE operating_system VARCHAR(50);
    DECLARE system_version VARCHAR(20);
    
    SET browser = ELT(FLOOR(1 + RAND() * 5), 'Chrome', 'Firefox', 'Safari', 'Edge', 'Opera');
    SET browser_version = ELT(FLOOR(1 + RAND() * 5), '110.0', '115.0', '16.6', '115.0', '102.0');

    -- Losowy wybór systemu operacyjnego i wersji
    SET operating_system = ELT(FLOOR(1 + RAND() * 5), 'Windows', 'macOS', 'Linux', 'Android', 'iOS');
    SET system_version = ELT(FLOOR(1 + RAND() * 5), '10', '11', '13.5', '22.04', '16.0');

    -- Łączenie w jeden string
    SET user_agent = CONCAT(browser, '/', browser_version, ' (', operating_system, ' ', system_version, ')');
    
    RETURN user_agent;
END$$

DROP FUNCTION IF EXISTS `generate_tracking_url`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `generate_tracking_url` (`shipping_details_id` BIGINT(20) UNSIGNED) RETURNS VARCHAR(255) CHARSET utf8mb4 COLLATE utf8mb4_general_ci  BEGIN
	DECLARE tracking_url VARCHAR(255);
    DECLARE destination_country CHAR(2);
    DECLARE shipping_provider_id BIGINT;
    DECLARE tracking_number VARCHAR(50) DEFAULT '';
    
    SELECT sd.country, sd.shipper_provider_id INTO destination_country, shipping_provider_id FROM shipping_details sd WHERE sd.shipping_details_id=shipping_details_id;
    
    -- Generowanie numeru śledzenia w zależności od dostawcy
    CASE shipping_provider_id
        WHEN 1 THEN -- DPD Polska
            SET tracking_number = LPAD(FLOOR(RAND() * 100000000000000), 14, '0');
        WHEN 2 THEN -- InPost
			FOR i IN 1..24 DO        	
        		SET tracking_number = CONCAT(tracking_number, FLOOR(RAND() * 10));
            END FOR;
        WHEN 3 THEN -- Poczta Polska
            SET tracking_number = CONCAT(
                'RR',
                LPAD(FLOOR(RAND() * 1000000000), 9, '0'),
                'PL'
            );
        WHEN 4 THEN -- GLS Poland
            SET tracking_number = LPAD(FLOOR(RAND() * 100000000000), 11, '0');
        WHEN 5 THEN -- DHL Parcel Polska
            SET tracking_number = LPAD(FLOOR(RAND() * 100000000000), 10, '0');
        WHEN 6 THEN -- FedEx
            SET tracking_number = LPAD(FLOOR(RAND() * 1000000000000), 12, '0');
        WHEN 7 THEN -- UPS Polska
            SET tracking_number = CONCAT(
                '1Z',
                UPPER(CONV(FLOOR(RAND() * 1000000), 10, 36)),
                LPAD(FLOOR(RAND() * 1000000000000), 12, '0')
            );
        WHEN 8 THEN -- Paczka w RUCHu
            SET tracking_number = LPAD(FLOOR(RAND() * 1000000000), 9, '0');
        ELSE
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nie można utworzyć numeru śledzenia dla podanego dostawcy.';
    END CASE;

    -- Generowanie linku śledzenia w zależności od dostawcy
    CASE shipping_provider_id
        WHEN 1 THEN -- DPD Polska
            IF destination_country = 'PL' THEN
                SET tracking_url = CONCAT('https://www.dpd.com/pl/pl/tracking?parcelNumber=', tracking_number);
            ELSE
                SET tracking_url = CONCAT('https://www.dpd.com/global/en/tracking?parcelNumber=', tracking_number);
            END IF;
        WHEN 2 THEN -- InPost
            SET tracking_url = CONCAT('https://inpost.pl/sledzenie-przesylek?number=', tracking_number);
        WHEN 3 THEN -- Poczta Polska
            SET tracking_url = CONCAT('https://emonitoring.poczta-polska.pl/?numer=', tracking_number);
        WHEN 4 THEN -- GLS Poland
            SET tracking_url = CONCAT('https://gls-group.com/PL/pl/sledzenie-paczek?match=', tracking_number);
        WHEN 5 THEN -- DHL Parcel Polska
            IF destination_country = 'PL' THEN
                SET tracking_url = CONCAT('https://www.dhl.com/pl-pl/home/tracking.html?tracking-id=', tracking_number);
            ELSE
                SET tracking_url = CONCAT('https://www.dhl.com/global-en/home/tracking.html?tracking-id=', tracking_number);
            END IF;
        WHEN 6 THEN -- FedEx
            SET tracking_url = CONCAT('https://www.fedex.com/fedextrack/?tracknumbers=', tracking_number);
        WHEN 7 THEN -- UPS Polska
            SET tracking_url = CONCAT('https://www.ups.com/track?loc=pl_PL&tracknum=', tracking_number);
        WHEN 8 THEN -- Paczka w RUCHu
            SET tracking_url = CONCAT('https://ruch.com.pl/sledzenie-przesylki?track_number=', tracking_number);
        ELSE
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nie można utworzyć linku dla podanego dostawcy.';
    END CASE;
    
    RETURN tracking_url;
END$$

DROP FUNCTION IF EXISTS `generate_transaction_id`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `generate_transaction_id` (`id_order` BIGINT(20) UNSIGNED) RETURNS VARCHAR(50) CHARSET utf8mb4 COLLATE utf8mb4_general_ci SQL SECURITY INVOKER BEGIN
	DECLARE transaction_id VARCHAR(50);
    DECLARE provider_id INT;
    
    SELECT payment_provider_id INTO provider_id FROM billing_details WHERE billing_details_id = (
        SELECT billing_details_id FROM cart WHERE cart_id = (
            SELECT cart_id FROM orders WHERE order_id=id_order
        )
	);
    
    -- Generowanie transaction_id na podstawie dostawcy
    CASE provider_id
        WHEN 1 THEN -- Przelewy24
            SET transaction_id = CONCAT('P24-', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'));
        WHEN 2 THEN -- PayU
            SET transaction_id = CONCAT('PU-', FLOOR(RAND() * 100000000));
        WHEN 3 THEN -- Blik
            SET transaction_id = CONCAT('BL-', FLOOR(RAND() * 1000000000));
        WHEN 4 THEN -- TPay
            SET transaction_id = CONCAT('TP-', UUID());
        WHEN 5 THEN -- DotPay
            SET transaction_id = CONCAT('DP-', DATE_FORMAT(NOW(), '%Y%m%d%H%i%s'));
        WHEN 6 THEN -- PayPal
            SET transaction_id = CONCAT('PP-', UUID());
        WHEN 7 THEN -- Apple Pay
            SET transaction_id = CONCAT('AP-', UUID());
        WHEN 8 THEN -- Google Pay
            SET transaction_id = CONCAT('GP-', UUID());
        WHEN 9 THEN -- MasterCard
            SET transaction_id = CONCAT('MC-', LPAD(FLOOR(RAND() * 1000000), 6, '0'));
        WHEN 10 THEN -- Visa
            SET transaction_id = CONCAT('VI-', LPAD(FLOOR(RAND() * 1000000), 6, '0'));
        ELSE
            -- Domyślna wartość dla nierozpoznanego dostawcy
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Brak podanego dostawcy płatności w bazie.";
    END CASE;

    RETURN transaction_id;

END$$

DROP FUNCTION IF EXISTS `remove_diacritics`$$
CREATE DEFINER=`judka_damian`@`%` FUNCTION `remove_diacritics` (`input_text` VARCHAR(255)) RETURNS VARCHAR(255) CHARSET utf8mb4 COLLATE utf8mb4_general_ci  BEGIN
	SET input_text = REPLACE(input_text, 'ą', 'a');
	SET input_text = REPLACE(input_text, 'ć', 'c');
	SET input_text = REPLACE(input_text, 'ę', 'e');
	SET input_text = REPLACE(input_text, 'ł', 'l');
	SET input_text = REPLACE(input_text, 'ń', 'n');
	SET input_text = REPLACE(input_text, 'ó', 'o');
	SET input_text = REPLACE(input_text, 'ś', 's');
	SET input_text = REPLACE(input_text, 'ź', 'z');
	SET input_text = REPLACE(input_text, 'ż', 'z');
    
    RETURN input_text;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `addresses`
--

DROP TABLE IF EXISTS `addresses`;
CREATE TABLE IF NOT EXISTS `addresses` (
  `address_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfiktator wiersza',
  `customer_id` bigint(20) UNSIGNED NOT NULL,
  `title` varchar(255) NOT NULL COMMENT 'Tytuł adresu (np. dom)',
  `address_line_1` varchar(100) NOT NULL COMMENT 'Pierwsza linia adresu',
  `address_line_2` varchar(100) DEFAULT NULL COMMENT 'Druga linia adresu',
  `country` char(2) NOT NULL COMMENT 'Adres - państwo (np. PL)',
  `city` varchar(255) NOT NULL COMMENT 'Adres - miasto',
  `state` varchar(255) DEFAULT NULL COMMENT 'Adres - stan (dotyczy USA)',
  `postal_code` varchar(12) NOT NULL COMMENT 'Adres - kod pocztowy',
  `phone_number` varchar(20) NOT NULL COMMENT 'Adres - numer telefonu',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia adresu',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Czas zaktualizowania adresu',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Czas usunięcia adresu',
  PRIMARY KEY (`address_id`),
  KEY `customer_fk` (`customer_id`)
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Adresy klienta (autouzupełnianie danych dostawy)';

--
-- Dumping data for table `addresses`
--

INSERT INTO `addresses` (`address_id`, `customer_id`, `title`, `address_line_1`, `address_line_2`, `country`, `city`, `state`, `postal_code`, `phone_number`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 18, ' Adres 1', 'Piłsudskiego Józefa Al. 64/63', NULL, 'PL', 'Otwock', NULL, '67-532', '(+48) 398138665', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(2, 9, ' Adres 2', 'Kochanowskiego Jana 04', NULL, 'PL', 'Chojnice', NULL, '50-243', '(+48) 620728285', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(3, 11, ' Mieszkanie - miasto', 'Bratków 32/51', NULL, 'PL', 'Jastarnia', NULL, '61-390', '(+48) 546097031', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(4, 12, ' Mieszkanie - miasto', 'Zwierzyniecka 74/87', NULL, 'PL', 'Zamość', NULL, '08-143', '(+48) 453018267', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(5, 19, ' Praca', 'Brzozowa 94A/48', NULL, 'PL', 'Świnoujście', NULL, '64-348', '(+48) 103410718', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(6, 18, ' Adres 2', 'Jagiellońskie Os. 68/70', NULL, 'PL', 'Ostróda', NULL, '16-274', '(+48) 559731608', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(7, 3, ' Akademik', 'Nowowiejska 65A', NULL, 'PL', 'Śrem', NULL, '32-280', '(+48) 508355322', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(8, 20, ' Praca', 'Kasprowicza Jana 40/02', NULL, 'PL', 'Szczawin', NULL, '89-242', '(+48) 107225231', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(9, 14, ' Mieszkanie - miasto', 'Podhalańska 15/64', NULL, 'PL', 'Koszalin', NULL, '87-016', '(+48) 227580736', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(10, 20, ' Adres 2', 'Słowackiego Juliusza 59A/18', NULL, 'PL', 'Krosno', NULL, '68-108', '(+48) 630209726', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(11, 17, ' Mieszkanie - miasto', 'Sienkiewicza Henryka 63A/65', NULL, 'PL', 'Kraśnik', NULL, '40-808', '(+48) 236290178', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(12, 11, 'Dom', 'Morska 04A', NULL, 'PL', 'Stargard Szczeciński', NULL, '83-116', '(+48) 537347585', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(13, 16, ' Mieszkanie - miasto', 'Okrężna 06', NULL, 'PL', 'Wyszków', NULL, '30-753', '(+48) 545890971', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(14, 20, ' Główny', 'Powstańców Śląskich 45A/59', NULL, 'PL', 'Świętochłowice', NULL, '27-443', '(+48) 549986173', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(15, 20, ' Adres 2', 'Wróblewskiego Walerego 16/60', NULL, 'PL', 'Mysłowice', NULL, '27-227', '(+48) 963498048', '2024-11-27 19:26:09', '2024-11-29 16:44:13', NULL),
(16, 1, 'Dom', 'ul. Kolorowa 5/21', NULL, 'PL', 'Nowy Sącz', NULL, '33-300', '(+48) 634837432', '2024-12-28 15:44:36', '2024-12-28 15:44:36', NULL),
(17, 2, 'Adres 1', 'Stara Wieś 95', NULL, 'PL', 'Limanowa', NULL, '34-600', '(+48) 294645834', '2024-12-30 21:58:12', '2024-12-30 21:58:12', NULL),
(18, 25, 'Dom', 'ul. Kolorowa 28', NULL, 'PL', 'Kraków', NULL, '31-366', '(+48) 764232234', '2025-01-05 08:27:11', '2025-01-05 08:27:11', NULL);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `attributes`
--

DROP TABLE IF EXISTS `attributes`;
CREATE TABLE IF NOT EXISTS `attributes` (
  `attribute_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `label` varchar(100) NOT NULL COMMENT 'Nazwa atrybutu produktu',
  `ident` varchar(100) NOT NULL COMMENT 'Identyfikator atrybutu produktu (niezmienny)',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia atrybutu produktu',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Czas usunięcia atrybutu produktu',
  PRIMARY KEY (`attribute_id`),
  UNIQUE KEY `attribute_label_idx` (`label`),
  UNIQUE KEY `attribute_ident_idx` (`ident`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Atrybuty produktu';

--
-- Dumping data for table `attributes`
--

INSERT INTO `attributes` (`attribute_id`, `label`, `ident`, `created_at`, `deleted_at`) VALUES
(1, 'Rozmiar produktu(S, 36)', 'SIZE', '2024-11-27 14:13:14', NULL),
(2, 'Kolor produktu(czerwony, błękitny)', 'COLOR', '2024-11-27 14:13:14', NULL),
(3, 'Wzór produktu(gładki, w paski)', 'PATTERN', '2024-11-27 14:13:14', NULL),
(4, 'Materiał, z którego jest wykonany produkt', 'FABRIC', '2024-11-27 14:13:14', NULL),
(5, 'Miara cieplna produktu(lekka, na zimę)', 'WARMTH_RATING', '2024-11-27 14:13:14', NULL),
(6, 'Krój(slim-fit, oversize)', 'FIT', '2024-11-27 14:13:14', NULL),
(7, 'Waga produktu', 'PRODUCT_WEIGHT', '2024-11-27 14:13:14', NULL),
(8, 'Obwód klatki piersiowej/talii/bioder', 'CHEST_WAIST_HIP', '2024-11-27 14:13:14', NULL),
(9, 'Rodzaj zapięcia produktu', 'CLOSURE', '2024-11-27 14:13:14', NULL),
(10, 'Dodatkowe funkcje(wodoodporność, kieszenie)', 'ADDITIONAL_FEATURES', '2024-11-27 14:13:14', NULL);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `billing_details`
--

DROP TABLE IF EXISTS `billing_details`;
CREATE TABLE IF NOT EXISTS `billing_details` (
  `billing_details_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'identyfikator wiersza',
  `payment_provider_id` bigint(20) UNSIGNED NOT NULL,
  `first_name` varchar(100) NOT NULL COMMENT 'imię klienta',
  `last_name` varchar(100) NOT NULL COMMENT 'nazwisko klienta',
  `email` varchar(255) NOT NULL COMMENT 'adres email klienta',
  `phone_number` varchar(20) NOT NULL COMMENT 'numer telefonu klienta',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'czas utworzenia szczegółów płatności',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'czas aktualizacji szczegółów płatności',
  PRIMARY KEY (`billing_details_id`),
  KEY `billing_provider_fk` (`payment_provider_id`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Szczegóły transakcji';

--
-- Dumping data for table `billing_details`
--

INSERT INTO `billing_details` (`billing_details_id`, `payment_provider_id`, `first_name`, `last_name`, `email`, `phone_number`, `created_at`, `updated_at`) VALUES
(1, 3, 'Helena', 'Baran', 'helena.baran@yahoo.com', '(+48) 634837432', '2024-12-28 18:02:56', '2024-12-28 18:02:56'),
(2, 4, 'Adrianna', 'Zielińska', 'adrianna98@gmail.com', '(+48) 294645834', '2024-12-30 21:58:43', '2024-12-30 22:03:26'),
(4, 5, 'Marianna', 'Zawadzka', 'marianna74@yahoo.com', '(+48) 537347585', '2025-01-02 16:47:05', '2025-01-02 16:47:05'),
(5, 1, 'Paweł', 'Kozłowski', 'pawel74@gmail.com', '(+48) 236290178', '2025-01-04 13:30:15', '2025-01-04 13:30:15'),
(6, 2, 'Róża', 'Witkowska', 'roza.witkowska@hotmail.com', '(+48) 723832123', '2025-01-04 14:10:22', '2025-01-04 14:10:22'),
(7, 5, 'Kacper', 'Gómulak', 'kacper.gomulak969@gmail.com', '(+48) 764232234', '2025-01-05 08:27:22', '2025-01-05 08:27:22');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `cart`
--

DROP TABLE IF EXISTS `cart`;
CREATE TABLE IF NOT EXISTS `cart` (
  `cart_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'identyfikator wiersza',
  `customer_id` bigint(20) UNSIGNED NOT NULL,
  `billing_details_id` bigint(20) UNSIGNED DEFAULT NULL,
  `shipping_details_id` bigint(20) UNSIGNED DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1 COMMENT 'status koszyka',
  `item_count` int(11) NOT NULL DEFAULT 0 COMMENT 'ilość produktów w koszyku',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'czas utworzenia koszyka',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'czas aktualizacji koszyka',
  PRIMARY KEY (`cart_id`),
  KEY `billing_details_fk` (`billing_details_id`),
  KEY `shipping_details_fk` (`shipping_details_id`),
  KEY `customer_fk` (`customer_id`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Koszyk klienta';

--
-- Dumping data for table `cart`
--

INSERT INTO `cart` (`cart_id`, `customer_id`, `billing_details_id`, `shipping_details_id`, `active`, `item_count`, `created_at`, `updated_at`) VALUES
(1, 1, 1, 1, 0, 2, '2024-12-26 14:27:14', '2025-01-02 16:35:27'),
(2, 2, 2, 2, 0, 1, '2024-12-26 14:27:14', '2025-01-02 19:29:14'),
(3, 3, NULL, NULL, 1, 2, '2024-12-26 14:27:14', '2024-12-30 20:41:28'),
(4, 4, NULL, NULL, 1, 1, '2024-12-26 14:27:14', '2024-12-30 20:39:56'),
(5, 5, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(6, 6, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(7, 7, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(8, 8, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(9, 9, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2025-01-04 17:12:37'),
(10, 10, 6, 6, 0, 1, '2024-12-26 14:27:14', '2025-01-04 17:06:05'),
(11, 11, 4, 4, 0, 1, '2024-12-26 14:27:14', '2025-01-02 20:18:19'),
(12, 12, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(13, 13, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(14, 14, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(15, 15, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(16, 16, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(17, 17, 5, 5, 0, 1, '2024-12-26 14:27:14', '2025-01-04 17:06:02'),
(18, 18, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(19, 19, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(20, 20, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(21, 21, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(22, 22, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(23, 23, NULL, NULL, 1, 0, '2024-12-26 14:27:14', '2024-12-26 14:27:14'),
(24, 24, NULL, NULL, 1, 0, '2025-01-04 19:08:16', '2025-01-04 19:08:16'),
(25, 25, 7, 7, 0, 1, '2025-01-05 07:58:48', '2025-01-05 08:27:22');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `cart_item`
--

DROP TABLE IF EXISTS `cart_item`;
CREATE TABLE IF NOT EXISTS `cart_item` (
  `item_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'identyfikator wiersza',
  `cart_id` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `quantity` int(11) NOT NULL DEFAULT 1 COMMENT 'ilość produktu',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'czas dodania produktu',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'czas aktualizacji produktu',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Czas usunięcia produktu z koszyka',
  PRIMARY KEY (`item_id`),
  KEY `cart_id` (`cart_id`),
  KEY `product_fk4` (`product_id`)
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Produkty w koszyku';

--
-- Dumping data for table `cart_item`
--

INSERT INTO `cart_item` (`item_id`, `cart_id`, `product_id`, `quantity`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 1, 36, 3, '2024-12-26 21:44:23', '2024-12-27 19:02:49', NULL),
(2, 1, 40, 2, '2024-12-26 21:46:02', '2024-12-26 21:46:02', NULL),
(3, 2, 36, 5, '2024-12-27 15:46:46', '2024-12-30 21:51:02', NULL),
(4, 3, 36, 2, '2024-12-30 20:14:13', '2024-12-30 20:14:13', NULL),
(5, 4, 20, 2, '2024-12-30 20:39:56', '2024-12-30 20:39:56', NULL),
(6, 3, 20, 100, '2024-12-30 20:41:28', '2024-12-30 20:41:28', NULL),
(7, 11, 50, 3, '2025-01-02 16:45:57', '2025-01-02 16:45:57', NULL),
(9, 9, 20, 1, '2025-01-03 23:10:59', '2025-01-04 17:12:37', '2025-01-04 17:12:37'),
(10, 17, 50, 1, '2025-01-03 23:18:47', '2025-01-03 23:19:43', NULL),
(11, 10, 33, 2, '2025-01-04 13:48:29', '2025-01-04 13:48:29', NULL),
(12, 25, 20, 1, '2025-01-05 08:02:36', '2025-01-05 08:02:36', NULL);

--
-- Wyzwalacze `cart_item`
--
DROP TRIGGER IF EXISTS `after_add_product_to_cart`;
DELIMITER $$
CREATE TRIGGER `after_add_product_to_cart` AFTER INSERT ON `cart_item` FOR EACH ROW BEGIN
	DECLARE id_customer BIGINT;
	
	UPDATE cart SET item_count = item_count + 1 WHERE cart_id=NEW.cart_id;
    
    SELECT customer_id INTO id_customer FROM cart WHERE cart_id=NEW.cart_id;
    CALL add_login_log('customer', id_customer, 'add_to_cart');
END
$$
DELIMITER ;
DROP TRIGGER IF EXISTS `after_delete_cart_item`;
DELIMITER $$
CREATE TRIGGER `after_delete_cart_item` AFTER UPDATE ON `cart_item` FOR EACH ROW BEGIN
	IF NEW.deleted_at IS NOT NULL THEN
    	UPDATE cart SET item_count = item_count - 1 WHERE cart_id=NEW.cart_id;
    END IF;
END
$$
DELIMITER ;
DROP TRIGGER IF EXISTS `before_add_product_to_cart`;
DELIMITER $$
CREATE TRIGGER `before_add_product_to_cart` BEFORE INSERT ON `cart_item` FOR EACH ROW BEGIN
	DECLARE product_type TEXT;
	SELECT type INTO product_type FROM products WHERE product_id = NEW.product_id;
    
    IF product_type = 'configurable' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = "Nie można dodać produktu typu 'configurable'!";
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `categories`
--

DROP TABLE IF EXISTS `categories`;
CREATE TABLE IF NOT EXISTS `categories` (
  `category_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `parent_id` bigint(20) UNSIGNED DEFAULT NULL COMMENT 'Identyfikator kategorii - rodzica',
  `category_name` varchar(255) NOT NULL COMMENT 'Nazwa kategorii',
  `category_description` text DEFAULT NULL COMMENT 'Opis kategorii',
  `left_node` int(11) DEFAULT NULL COMMENT 'Identyfikator kategorii po lewej stronie drzewa hierarchi',
  `right_node` int(11) DEFAULT NULL COMMENT 'Identyfikator kategorii po prawej stronie drzewa hierarchi',
  `level` int(11) NOT NULL COMMENT 'Stopień zagnieżdżania kategorii',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia kategorii',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Czas usunięcia kategorii',
  PRIMARY KEY (`category_id`),
  KEY `parent_category_fk` (`parent_id`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=94 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Kategorie produktów';

--
-- Dumping data for table `categories`
--

INSERT INTO `categories` (`category_id`, `parent_id`, `category_name`, `category_description`, `left_node`, `right_node`, `level`, `created_at`, `deleted_at`) VALUES
(1, NULL, 'zakupy', 'Kategoria początkowa - korzeń', 2, 3, 1, '2024-11-25 23:38:47', NULL),
(2, 1, 'dla kobiet', 'Kategoria produktów dla kobiet', 4, 6, 2, '2024-11-26 00:02:49', NULL),
(3, 1, 'dla mężczyzn', 'Kategoria produktów dla mężczyzn', 7, 9, 2, '2024-11-26 00:11:21', NULL),
(4, 2, 'odzież', 'Podkategoria dla kobiet ', 10, 19, 3, '2024-11-26 00:17:53', NULL),
(5, 2, 'buty', 'Podkategoria dla kobiet', 20, 29, 3, '2024-11-26 00:17:53', NULL),
(6, 2, 'akcesoria', 'Podkategoria dla kobiet', 30, 37, 3, '2024-11-26 00:17:53', NULL),
(7, 3, 'odzież', 'Podkategoria dla mężczyzn', 38, 45, 3, '2024-11-26 00:18:17', NULL),
(8, 3, 'buty', 'Podkategoria dla mężczyzn', 46, 53, 3, '2024-11-26 00:18:17', NULL),
(9, 3, 'akcesoria', 'Podkategoria dla mężczyzn', 54, 63, 3, '2024-11-26 00:18:17', NULL),
(10, 4, 'płaszcze', 'Podkategoria odzieży dla kobiet', NULL, NULL, 4, '2024-11-26 00:17:53', NULL),
(11, 4, 'kurtki', 'Podkategoria odzieży dla kobiet', 64, 66, 4, '2024-11-26 00:17:53', NULL),
(12, 4, 'bluzy', 'Podkategoria odzieży dla kobiet', 67, 69, 4, '2024-11-26 00:17:53', NULL),
(13, 4, 'swetry', 'Podkategoria odzieży dla kobiet', NULL, NULL, 4, '2024-11-26 00:17:53', NULL),
(14, 4, 'sukienki', 'Podkategoria odzieży dla kobiet', NULL, NULL, 4, '2024-11-26 00:17:53', NULL),
(15, 4, 'topy', 'Podkategoria odzieży dla kobiet', NULL, NULL, 4, '2024-11-26 00:17:53', NULL),
(16, 4, 'koszulki', 'Podkategoria odzieży dla kobiet', 70, 72, 4, '2024-11-26 00:17:53', NULL),
(17, 4, 'koszule', 'Podkategoria odzieży dla kobiet', NULL, NULL, 4, '2024-11-26 00:17:53', NULL),
(18, 4, 'spodnie', 'Podkategoria odzieży dla kobiet', 73, 75, 4, '2024-11-26 00:17:53', NULL),
(19, 4, 'spódnice', 'Podkategoria odzieży dla kobiet', NULL, NULL, 4, '2024-11-26 00:17:53', NULL),
(20, 5, 'botki, kozaki', 'Podkategoria butów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:33', NULL),
(21, 5, 'trzewiki', 'Podkategoria butów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:33', NULL),
(22, 5, 'platformy', 'Podkategoria butów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:33', NULL),
(23, 5, 'na obcasie', 'Podkategoria butów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:33', NULL),
(24, 5, 'półbuty', 'Podkategoria butów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:33', NULL),
(25, 5, 'sportowe', 'Podkategoria butów dla kobiet', 76, 78, 4, '2024-11-26 00:25:33', NULL),
(26, 5, 'trampki', 'Podkategoria butów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:33', NULL),
(27, 5, 'baleriny', 'Podkategoria butów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:33', NULL),
(28, 5, 'klapki, japonki', 'Podkategoria butów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:33', NULL),
(29, 5, 'sandały', 'Podkategoria butów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:33', NULL),
(30, 6, 'piżamy, szlafroki', 'Podkategoria akcesoriów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:40', NULL),
(31, 6, 'kapcie', 'Podkategoria akcesoriów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:40', NULL),
(32, 6, 'skarpetki, rajstopy', 'Podkategoria akcesoriów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:40', NULL),
(33, 6, 'bielizna', 'Podkategoria akcesoriów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:40', NULL),
(34, 6, 'czapki', 'Podkategoria akcesoriów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:40', NULL),
(35, 6, 'szaliki, rękawiczki', 'Podkategoria akcesoriów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:40', NULL),
(36, 6, 'torby', 'Podkategoria akcesoriów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:40', NULL),
(37, 6, 'paski', 'Podkategoria akcesoriów dla kobiet', NULL, NULL, 4, '2024-11-26 00:25:40', NULL),
(38, 7, 'płaszcze', 'Podkategoria odzieży dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:18:17', NULL),
(39, 7, 'kurtki', 'Podkategoria odzieży dla mężczyzn', 79, 81, 4, '2024-11-26 00:18:17', NULL),
(40, 7, 'bluzy', 'Podkategoria odzieży dla mężczyzn', 82, 84, 4, '2024-11-26 00:18:17', NULL),
(41, 7, 'swetry', 'Podkategoria odzieży dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:18:17', NULL),
(42, 7, 'koszulki', 'Podkategoria odzieży dla mężczyzn', 85, 87, 4, '2024-11-26 00:18:17', NULL),
(43, 7, 'koszule', 'Podkategoria odzieży dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:18:17', NULL),
(44, 7, 'spodnie', 'Podkategoria odzieży dla mężczyzn', 88, 90, 4, '2024-11-26 00:18:17', NULL),
(45, 7, 'szorty', 'Podkategoria odzieży dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:18:17', NULL),
(46, 8, 'zimowe', 'Podkategoria butów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:43', NULL),
(47, 8, 'sportowe', 'Podkategoria butów dla mężczyzn', 91, 93, 4, '2024-11-26 00:29:43', NULL),
(48, 8, 'sneakersy', 'Podkategoria butów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:43', NULL),
(49, 8, 'trampki', 'Podkategoria butów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:43', NULL),
(50, 8, 'za kostkę', 'Podkategoria butów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:43', NULL),
(51, 8, 'klapki, japonki', 'Podkategoria butów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:43', NULL),
(52, 8, 'sandały', 'Podkategoria butów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:43', NULL),
(53, 8, 'eleganckie', 'Podkategoria butów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:43', NULL),
(54, 9, 'piżamy, szlafroki', 'Podkategoria akcesoriów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:55', NULL),
(55, 9, 'kapcie', 'Podkategoria akcesoriów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:55', NULL),
(56, 9, 'skarpetki', 'Podkategoria akcesoriów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:55', NULL),
(57, 9, 'czapki', 'Podkategoria akcesoriów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:55', NULL),
(58, 9, 'rękawiczki', 'Podkategoria akcesoriów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:55', NULL),
(59, 9, 'kominy, szaliki', 'Podkategoria akcesoriów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:55', NULL),
(60, 9, 'paski', 'Podkategoria akcesoriów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:55', NULL),
(61, 9, 'krawaty', 'Podkategoria akcesoriów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:55', NULL),
(62, 9, 'bielizna', 'Podkategoria akcesoriów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:55', NULL),
(63, 9, 'nerki, plecaki', 'Podkategoria akcesoriów dla mężczyzn', NULL, NULL, 4, '2024-11-26 00:29:55', NULL),
(64, 11, 'futra', 'Podkategoria kurtek dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(65, 11, 'skórzane', 'Podkategoria kurtek dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(66, 11, 'puchowe', 'Podkategoria kurtek dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(67, 12, 'z kapturem', 'Podkategoria bluz dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(68, 12, 'bez kaptura', 'Podkategoria bluz dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(69, 12, 'rozpinane', 'Podkategoria bluz dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(70, 16, 'oversize', 'Podkategoria koszulek dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(71, 16, 'basic', 'Podkategoria koszulek dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(72, 16, 'bezrękawniki', 'Podkategoria koszulek dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(73, 18, 'dresy', 'Podkategoria spodni dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(74, 18, 'jeansy', 'Podkategoria spodni dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(75, 18, 'joggery', 'Podkategoria spodni dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(76, 25, 'do biegania', 'Podkategoria butów sportowych dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(77, 25, 'lifestyle', 'Podkategoria butów sportowych dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(78, 25, 'treningowe', 'Podkategoria butów sportowych dla kobiet', NULL, NULL, 5, '2024-11-26 00:17:53', NULL),
(79, 39, 'futra', 'Podkategoria kurtek dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:27', NULL),
(80, 39, 'skórzane', 'Podkategoria kurtek dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:27', NULL),
(81, 39, 'puchowe', 'Podkategoria kurtek dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:27', NULL),
(82, 40, 'z kapturem', 'Podkategoria bluz dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:33', NULL),
(83, 40, 'bez kaptura', 'Podkategoria bluz dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:33', NULL),
(84, 40, 'rozpinane', 'Podkategoria bluz dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:33', NULL),
(85, 42, 'oversize', 'Podkategoria koszulek dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:40', NULL),
(86, 42, 'basic', 'Podkategoria koszulek dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:40', NULL),
(87, 42, 'bezrękawniki', 'Podkategoria koszulek dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:40', NULL),
(88, 44, 'dresy', 'Podkategoria spodni dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:45', NULL),
(89, 44, 'jeansy', 'Podkategoria spodni dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:45', NULL),
(90, 44, 'joggery', 'Podkategoria spodni dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:45', NULL),
(91, 47, 'do biegania', 'Podkategoria butów sportowych dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:50', NULL),
(92, 47, 'lifestyle', 'Podkategoria butów sportowych dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:50', NULL),
(93, 47, 'treningowe', 'Podkategoria butów sportowych dla mężczyzn', NULL, NULL, 5, '2024-11-26 00:34:50', NULL);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `category_product`
--

DROP TABLE IF EXISTS `category_product`;
CREATE TABLE IF NOT EXISTS `category_product` (
  `category_product_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `category_id` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  PRIMARY KEY (`category_product_id`),
  KEY `category_fk` (`category_id`),
  KEY `product_fk` (`product_id`)
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Tabela pivotowa łącząca kategorię z produktem';

--
-- Dumping data for table `category_product`
--

INSERT INTO `category_product` (`category_product_id`, `category_id`, `product_id`) VALUES
(1, 91, 1),
(2, 67, 2),
(3, 92, 3),
(4, 86, 4),
(5, 53, 5),
(6, 45, 6),
(7, 78, 7),
(8, 53, 8),
(9, 89, 9),
(10, 83, 10),
(11, 69, 11),
(12, 41, 12),
(13, 74, 13),
(14, 71, 14),
(15, 71, 15),
(16, 67, 16),
(17, 33, 17),
(18, 73, 18),
(19, 53, 19),
(20, 37, 20),
(21, 63, 21),
(22, 53, 22),
(23, 66, 23),
(24, 36, 24),
(25, 81, 25),
(26, 88, 26),
(27, 64, 27),
(28, 81, 28),
(29, 43, 29),
(30, 89, 30),
(31, 86, 31),
(32, 66, 32);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `customers`
--

DROP TABLE IF EXISTS `customers`;
CREATE TABLE IF NOT EXISTS `customers` (
  `customer_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `first_name` varchar(100) NOT NULL COMMENT 'Imię klienta sklepu',
  `last_name` varchar(100) NOT NULL COMMENT 'Nazwisko klienta sklepu',
  `date_of_birth` date NOT NULL COMMENT 'Data urodzenia klienta sklepu',
  `email` varchar(255) NOT NULL COMMENT 'Email klienta sklepu',
  `password` varchar(64) NOT NULL COMMENT 'Hasło klienta sklepu',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia klienta sklepu',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Czas zaktualizowania klienta sklepu',
  PRIMARY KEY (`customer_id`),
  UNIQUE KEY `customer_email_index` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Klienci sklepu';

--
-- Dumping data for table `customers`
--

INSERT INTO `customers` (`customer_id`, `first_name`, `last_name`, `date_of_birth`, `email`, `password`, `created_at`, `updated_at`) VALUES
(1, 'Helena', 'Baran', '1980-07-06', 'helena.baran@yahoo.com', '35ffa767424579d91a8deca200d6169b298e954ba6858b0401d4ebc265358fdf', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(2, 'Adrianna', 'Zielińska', '1976-03-08', 'adrianna98@gmail.com', '358e2af77dbe61ad9902afc6e8c64ff71bb5c6fa2849cda5430aacb7d6941044', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(3, 'Artur', 'Pawłowski', '2005-04-30', 'artur50@hotmail.com', 'fc64da05c3fdb2f194fe05cd68b90c13fe9fb83cf3812570836c44aee8791f08', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(4, 'Patryk', 'Kamiński', '1997-01-06', 'pkaminski@hotmail.com', 'dc762cea613020b4cb5e11a7996796cd8fccbd3b61b4c1953afbf39ab5ef48ee', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(5, 'Anna', 'Kamińska', '1982-10-17', 'anna.kaminska@gmail.com', 'b83a815bb413237331461a9060a5a156d3ba52f384d0550dac999421ffdc1801', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(6, 'Martyna', 'Stępień', '1975-06-04', 'mstepien@hotmail.com', '9a1075696f3bbf0cf77812ece342b93a6a1cffb31223881bd094f7469c721bc7', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(7, 'Marika', 'Brzeziński', '1970-04-21', 'marika.brzezinska@gmail.com', '5ad4355a02864e0a4db5b212b17998d315dfcd57df11d0370528b9cfca8a958c', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(8, 'Aurelia', 'Król', '1996-11-04', 'aurelia.krol@yahoo.com', '3fa1e3bac6d05f07514d512c03ab9c7fbb80852710b24ea7840ec6f3772db371', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(9, 'Dariusz', 'Wróbel', '1983-03-22', 'dwrobel@yahoo.com', '3d51b1c5b7cadf3d5d6623c2f1d73edd44c6b19fa71c9b2a079c365dfc6a04c9', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(10, 'Róża', 'Witkowska', '1993-07-28', 'roza.witkowska@hotmail.com', '59614c198c92cd424ecf13d0aa32f6a97365872ebb77e0e864692b1dd4d86251', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(11, 'Marianna', 'Zawadzka', '1991-07-06', 'marianna74@yahoo.com', '775cbe66663a6c93aca111d133c240a94a76a49cf64e054f9031e9de509d5887', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(12, 'Kamil', 'Czarnecka', '1972-12-18', 'kczarnecka@hotmail.com', 'c5be56bbd55b6406910198d957eac80481e73fb6d24ba2299c172ed238236f95', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(13, 'Liwia', 'Dąbrowska', '1986-02-19', 'liwia.dabrowska@hotmail.com', '972397d73615b6848268738f4b218e299a0728c044dc0291791b6584de55e277', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(14, 'Ryszard', 'Wasilewski', '1981-12-03', 'rwasilewski@hotmail.com', 'aa8587b7243d2c13a54cc6a311b6ce5ddd06f81e1c3da66e772074364fb6aeee', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(15, 'Gabriela', 'Szymczak', '1997-12-21', 'gabriela03@yahoo.com', 'a7ccfd46528094a90d91a892a832c0d363f031a680938849b6105d335f384169', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(16, 'Leon', 'Wysocki', '1970-12-20', 'leon.wysocki@yahoo.com', '9fc7e10263cc771a8246b3e1ec70dc2e51479ee22690024c862432d9b7098b2c', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(17, 'Paweł', 'Kozłowski', '1973-08-23', 'pawel74@gmail.com', '6369087c529a8f097aed82c23ea524086fc3fac6c3748ab03504b8d4dcfc56ef', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(18, 'Melania', 'Kamińska', '1971-04-20', 'melania.kaminska@hotmail.com', 'feeed8237c6ea5ed7c94d6dd94879c24580ef95d7a67b8fa5e13d5858d8d09b2', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(19, 'Miłosz', 'Laskowski', '2008-08-02', 'milosz.laskowski@hotmail.com', 'bae82ba0e1a8274d7041f2a3daf734991afd52b261cb49a93ffcbfc5550632c3', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(20, 'Klaudia', 'Konieczny', '1991-04-26', 'konieczny.klaudia@gmail.com', '07803bc2cf72f7cd0422bb55098fb6481c3744d58eac668630bf5b6749bfa00b', '2024-11-27 16:52:57', '2024-11-27 18:36:08'),
(21, 'Jakub', 'Domagała', '1982-03-26', 'jakub.domagala4325@gmail.com', '3abccafb0069fa0ff50445565e2e45606f21416ca28aa7cfafcb9f59170a698d', '2024-12-17 22:50:57', '2024-12-17 22:50:57'),
(22, 'Natalia', 'Czyżyńska', '1980-07-17', 'natalia.czyzynska3666@gmail.com', '888cd14898c6e1dd1574e535da5175a80d796105a19c9f331365931c3821cd96', '2024-12-18 20:29:30', '2024-12-18 20:29:30'),
(23, 'Paweł', 'Załubski', '1987-01-18', 'pawel.zalubski6315@gmail.com', 'd223bb60464d64d32c44854ce78ad281621e9d023f53e6abc1fd35c7f342f990', '2024-12-19 15:51:29', '2024-12-19 15:56:16'),
(24, 'Henryk', 'Mątwa', '1977-07-17', 'henryk.matwa9889@gmail.com', '1ec6e45ae07f918c58cfe82602c9b8716cff082e2258bbc9acc28c2ce62b47c4', '2025-01-04 19:08:16', '2025-01-04 19:08:16'),
(25, 'Kacper', 'Gómulak', '1991-10-08', 'kacper.gomulak969@gmail.com', 'd95e3a9704fceffd6512bcd7c9600d5150c1dfd4fba237a662cfeba2d8584e66', '2025-01-05 07:58:48', '2025-01-05 07:58:48');

--
-- Wyzwalacze `customers`
--
DROP TRIGGER IF EXISTS `insert_cart`;
DELIMITER $$
CREATE TRIGGER `insert_cart` AFTER INSERT ON `customers` FOR EACH ROW BEGIN
    INSERT INTO cart (customer_id)
    VALUES (NEW.customer_id);
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `invoices`
--

DROP TABLE IF EXISTS `invoices`;
CREATE TABLE IF NOT EXISTS `invoices` (
  `invoice_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyrfikator wiersza',
  `order_id` bigint(20) UNSIGNED NOT NULL,
  `external_transaction_id` varchar(100) NOT NULL COMMENT 'Identyfikator transakcji',
  `total_net` int(11) NOT NULL COMMENT 'Wartość netto faktury',
  `total_gross` int(11) NOT NULL COMMENT 'Wartość brutto',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia faktury',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Czas zaktualizowania faktury',
  PRIMARY KEY (`invoice_id`),
  UNIQUE KEY `order_fk` (`order_id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Faktury';

--
-- Dumping data for table `invoices`
--

INSERT INTO `invoices` (`invoice_id`, `order_id`, `external_transaction_id`, `total_net`, `total_gross`, `created_at`, `updated_at`) VALUES
(1, 1, 'BL-41867267', 99000, 121770, '2025-01-01 18:27:54', '2025-01-01 18:27:54'),
(2, 3, 'DP-20250102211819', 39000, 47970, '2025-01-02 20:18:19', '2025-01-02 20:18:19'),
(3, 6, 'DP-20250105093130', 210000, 258300, '2025-01-05 08:31:30', '2025-01-05 08:31:30');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `invoice_lines`
--

DROP TABLE IF EXISTS `invoice_lines`;
CREATE TABLE IF NOT EXISTS `invoice_lines` (
  `invoice_line_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `invoice_id` bigint(20) UNSIGNED NOT NULL,
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `quantity` int(11) NOT NULL COMMENT 'Ilość produktu na fakturze',
  `unit_cost_net` int(11) NOT NULL COMMENT 'Wartość netto produktu na fakturze',
  `tax_class` int(11) NOT NULL COMMENT 'Stawka podatku VAT produktu na fakturze',
  `line_total_net` int(11) NOT NULL COMMENT 'Całkowita wartość netto produktu na fakturze',
  PRIMARY KEY (`invoice_line_id`),
  KEY `invoice_fk` (`invoice_id`) USING BTREE,
  KEY `product_fk` (`product_id`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Pozycje na fakturze';

--
-- Dumping data for table `invoice_lines`
--

INSERT INTO `invoice_lines` (`invoice_line_id`, `invoice_id`, `product_id`, `quantity`, `unit_cost_net`, `tax_class`, `line_total_net`) VALUES
(1, 1, 36, 3, 25000, 23, 75000),
(2, 1, 40, 2, 12000, 23, 24000),
(3, 2, 50, 3, 13000, 23, 39000),
(4, 3, 20, 1, 210000, 23, 210000);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `login_history`
--

DROP TABLE IF EXISTS `login_history`;
CREATE TABLE IF NOT EXISTS `login_history` (
  `login_history_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'identyfikator wiersza',
  `user_id` bigint(20) UNSIGNED DEFAULT NULL,
  `customer_id` bigint(20) UNSIGNED DEFAULT NULL,
  `ip_address` varchar(15) NOT NULL COMMENT 'adres ip użytkownika',
  `user_agent` varchar(255) NOT NULL COMMENT 'informacja o wersji przeglądarki i systemie operacyjnym użytkownika',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'czas utworzenia historii użytkownika',
  PRIMARY KEY (`login_history_id`),
  KEY `user_fk` (`user_id`) USING BTREE,
  KEY `customer_fk` (`customer_id`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=13 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Historia logowania użytkownika';

--
-- Dumping data for table `login_history`
--

INSERT INTO `login_history` (`login_history_id`, `user_id`, `customer_id`, `ip_address`, `user_agent`, `created_at`) VALUES
(1, NULL, 9, '211.165.194.217', 'Opera/115.0 (Android 11)', '2025-01-03 22:47:40'),
(2, NULL, 17, '209.53.146.62', 'Safari/115.0 (Windows 13.5)', '2025-01-03 23:05:24'),
(3, NULL, 10, '79.92.221.66', 'Edge/115.0 (macOS 11)', '2025-01-04 13:30:07'),
(10, NULL, 10, '101.119.37.82', 'Chrome/102.0 (iOS 10)', '2025-01-04 15:42:21'),
(11, NULL, 25, '102.141.142.31', 'Opera/115.0 (Android 16.0)', '2025-01-05 07:35:50'),
(12, NULL, 25, '173.191.184.92', 'Edge/110.0 (Linux 16.0)', '2025-01-05 07:56:51');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `orders`
--

DROP TABLE IF EXISTS `orders`;
CREATE TABLE IF NOT EXISTS `orders` (
  `order_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'identyfikator wiersza',
  `customer_id` bigint(20) UNSIGNED NOT NULL,
  `cart_id` bigint(20) UNSIGNED NOT NULL,
  `status` enum('placed','paid','ready_to_ship','shipped') NOT NULL COMMENT 'status zamówienia',
  `tracking_url` varchar(255) DEFAULT NULL COMMENT 'Link do śledzenia przesyłki',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'czas utworzenia zamówienia',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'czas aktualizacji zamówienia',
  PRIMARY KEY (`order_id`),
  UNIQUE KEY `cart_FK` (`cart_id`) USING BTREE,
  KEY `customer_fk3` (`customer_id`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Dane zamówienia';

--
-- Dumping data for table `orders`
--

INSERT INTO `orders` (`order_id`, `customer_id`, `cart_id`, `status`, `tracking_url`, `created_at`, `updated_at`) VALUES
(1, 1, 1, 'shipped', 'https://inpost.pl/sledzenie-przesylek?number=187473603447219261060550', '2024-12-28 19:07:31', '2025-01-02 18:34:27'),
(2, 2, 2, 'placed', NULL, '2024-12-30 21:58:43', '2024-12-30 21:58:43'),
(3, 11, 11, 'shipped', 'https://www.fedex.com/fedextrack/?tracknumbers=792955629334', '2025-01-02 16:47:05', '2025-01-02 20:23:35'),
(4, 17, 17, 'placed', NULL, '2025-01-04 13:30:15', '2025-01-04 13:30:15'),
(5, 10, 10, 'placed', NULL, '2025-01-04 16:27:41', '2025-01-04 16:27:41'),
(6, 25, 25, 'shipped', 'https://www.fedex.com/fedextrack/?tracknumbers=983441836185', '2025-01-05 08:27:22', '2025-01-05 08:36:17');

--
-- Wyzwalacze `orders`
--
DROP TRIGGER IF EXISTS `after_add_order`;
DELIMITER $$
CREATE TRIGGER `after_add_order` AFTER INSERT ON `orders` FOR EACH ROW BEGIN
	CALL change_stock_level(NEW.order_id, NEW.cart_id, 'order_placed');
    CALL add_login_log('customer', NEW.customer_id, 'add_order');
END
$$
DELIMITER ;
DROP TRIGGER IF EXISTS `after_ship_order`;
DELIMITER $$
CREATE TRIGGER `after_ship_order` AFTER UPDATE ON `orders` FOR EACH ROW BEGIN
	IF NEW.status = 'shipped' THEN
    	CALL change_stock_level(NEW.order_id, NEW.cart_id, 'order_dispatched');
    END IF;
END
$$
DELIMITER ;
DROP TRIGGER IF EXISTS `before_add_order`;
DELIMITER $$
CREATE TRIGGER `before_add_order` BEFORE INSERT ON `orders` FOR EACH ROW BEGIN
	DECLARE number_of_items INT;
    DECLARE existing_not_paid_id INT DEFAULT 0;
    
    SELECT item_count INTO number_of_items FROM cart WHERE cart_id=NEW.cart_id;
    
    IF number_of_items = 0 THEN
    	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Brak produktów w koszyku!";
    END IF;
    
    SELECT order_id INTO existing_not_paid_id FROM orders WHERE cart_id=NEW.cart_id AND status='placed' LIMIT 1;
    
    IF existing_not_paid_id > 0 THEN
    	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Aby złożyć nowe zamówienie, opłać inne zamówienia.";
    END IF;
END
$$
DELIMITER ;
DROP TRIGGER IF EXISTS `before_update_order`;
DELIMITER $$
CREATE TRIGGER `before_update_order` BEFORE UPDATE ON `orders` FOR EACH ROW BEGIN

	DECLARE invalid_order_id BIGINT;
	
    SELECT order_id INTO invalid_order_id FROM stock_events WHERE order_id=NEW.order_id AND event_type='order_cancelled';
    
    IF invalid_order_id > 0 THEN
    	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT="Zamówienie anulowane.";
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `payment_providers`
--

DROP TABLE IF EXISTS `payment_providers`;
CREATE TABLE IF NOT EXISTS `payment_providers` (
  `payment_provider_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `label` varchar(100) NOT NULL COMMENT 'Nazwa dostawcy płatności',
  `ident` varchar(100) NOT NULL COMMENT 'Identyfikator dostawcy płatności (niezmienny)',
  `description` varchar(255) NOT NULL COMMENT 'Opis dostawcy płatności',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas dodania dostawcy płatności',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Czas zaktualizowania dostawcy płatności',
  PRIMARY KEY (`payment_provider_id`) USING BTREE,
  UNIQUE KEY `payment_provider_label_idx` (`label`) USING BTREE,
  UNIQUE KEY `payment_provider_ident_idx` (`ident`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Dostawcy płatności';

--
-- Dumping data for table `payment_providers`
--

INSERT INTO `payment_providers` (`payment_provider_id`, `label`, `ident`, `description`, `created_at`, `updated_at`) VALUES
(1, 'Przelewy24', 'PRZELEWY_24', 'Polski system płatności online umożliwiający szybkie przelewy i płatności kartą.', '2024-11-27 14:48:31', '2024-01-29 19:25:31'),
(2, 'PayU', 'PAYU', 'Jeden z największych dostawców płatności online w Polsce, obsługujący płatności kartami, przelewami i Blik.', '2024-11-27 14:48:31', '2024-03-30 19:25:31'),
(3, 'Blik', 'BLIK', 'Polski system płatności mobilnych umożliwiający szybkie transakcje poprzez aplikację bankową.', '2024-11-27 14:48:31', '2024-04-01 18:25:31'),
(4, 'Tpay', 'TPAY', 'Polski operator płatności online, specjalizujący się w przelewach i płatnościach kartą.', '2024-11-27 14:48:31', '2024-05-02 18:25:32'),
(5, 'Dotpay', 'DOTPAY', 'Polski dostawca usług płatności online obsługujący szybkie przelewy i płatności kartą.', '2024-11-27 14:48:31', '2024-06-03 18:25:32'),
(6, 'PayPal', 'PAYPAL', 'Globalny dostawca płatności online, umożliwiający płatności kartą, portfelem cyfrowym i przelewami.', '2024-11-27 14:48:31', '2024-07-04 18:25:32'),
(7, 'Apple Pay', 'APPLE_PAY', 'System płatności mobilnych i portfela cyfrowego dla urządzeń Apple.', '2024-11-27 14:48:31', '2024-08-05 18:25:32'),
(8, 'Google Pay', 'GOOGLE_PAY', 'Platforma płatności cyfrowych dostępna na urządzeniach z systemem Android.', '2024-11-27 14:48:31', '2024-09-06 18:25:32'),
(9, 'Mastercard', 'MASTERCARD', 'Globalny dostawca usług płatniczych, w tym kart płatniczych i cyfrowych rozwiązań płatniczych.', '2024-11-27 14:48:31', '2024-10-07 18:25:32'),
(10, 'Visa', 'VISA', 'Międzynarodowy lider w dziedzinie płatności kartami i portfeli cyfrowych.', '2024-11-27 14:48:31', '2024-11-08 19:25:33');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `permissions`
--

DROP TABLE IF EXISTS `permissions`;
CREATE TABLE IF NOT EXISTS `permissions` (
  `permission_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `label` varchar(100) NOT NULL COMMENT 'Nazwa uprawnienia użytkownika',
  `ident` varchar(100) NOT NULL COMMENT 'Identyfikator uprawnienia użytkownika (niezmienny)',
  `descritption` varchar(255) DEFAULT NULL COMMENT 'Opis uprawnienia użytkownika',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia uprawnienia użytkownika',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Czas zaktualizownia uprawnienia użytkownika',
  PRIMARY KEY (`permission_id`),
  UNIQUE KEY `permisssion_label_index` (`label`),
  UNIQUE KEY `permission_ident_index` (`ident`)
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Uprawnienia użytkownika';

--
-- Dumping data for table `permissions`
--

INSERT INTO `permissions` (`permission_id`, `label`, `ident`, `descritption`, `created_at`, `updated_at`) VALUES
(1, 'Zarządzanie zamówieniami', 'MANAGE_ORDERS', 'Dostęp do zamówień klientów i operacji na nich (edytowania i tworzenia)', '2024-11-18 18:47:20', '2024-11-29 17:37:25'),
(2, 'Zarządzanie zwrotami zamówień', 'MANAGE_RETURNS', 'Dostęp do widoku i obsługi zwrotów produktów', '2024-11-18 18:51:38', '2024-11-29 17:43:57'),
(3, 'Zarządzanie klientami sklepu', 'MANAGE_CUSTOMERS', 'Dostęp do edytowania danych klientów', '2024-11-18 18:53:55', '2024-11-29 17:43:58'),
(4, 'Zarządzanie opiniami produktów', 'MANAGE_REVIEWS', 'Dostęp do edytowania i usuwania opinii produktów', '2024-11-18 19:02:16', '2024-11-29 17:50:15'),
(5, 'Zarządzanie kodami rabatowymi', 'MANAGE_LEGACY_COUPONS', 'Dostęp do edytowania, dodawania i usuwania kodów rabatowych', '2024-11-18 19:05:21', '2024-11-29 17:50:15'),
(6, 'Zarządzanie akcjami promocyjnymi', 'MANAGE_PROMOTIONS', 'Dostęp do edytowania, dodawania i usuwania akcji promocyjnych', '2024-11-18 19:08:16', '2024-11-29 17:57:42'),
(7, 'Zarządzanie stronami sklepu', 'MANAGE_PAGES', 'Dostęp do tworzenia, edytowania i usuwania stron sklepu za pomocą HTML', '2024-11-18 19:13:18', '2024-11-29 17:57:42'),
(8, 'Zarządzanie banerami na stronach sklepu', 'MANAGE_BANNERS', 'Dostęp do tworzenia, edytowania i usuwania banerów na stronach sklepu', '2024-11-18 19:17:35', '2024-11-29 18:02:48'),
(9, 'Zarządzanie produktami', 'MANAGE_PRODUCTS', 'Dostęp do tworzenia, edytowania i usuwania produktów', '2024-11-18 20:50:36', '2024-11-29 18:02:48'),
(10, 'Zarządzanie kategoriami produktów', 'MANAGE_CATEGORIES', 'Dostęp do tworzenia, edytowania i usuwania kategorii produktów', '2024-11-18 20:50:36', '2024-11-29 18:10:19'),
(11, 'Zarządzanie użytkownikami systemu', 'MANAGE_USERS', 'Dostęp do dodawania, edytowania i usuwania użytkowników systemu', '2024-11-18 21:01:49', '2024-11-29 18:10:19'),
(12, 'Zarządzanie ustawieniami płatności', 'MANAGE_PAYMENTS', 'Dostęp do ustawień płatności', '2024-11-29 18:24:11', '2024-11-29 18:24:11'),
(13, 'Zarządzanie ustawieniami wysyłki', 'MANAGE_SHIPPING', 'Dostęp do ustawień wysyłki', '2024-11-29 18:24:11', '2024-11-29 18:24:11'),
(14, 'Zarządzanie logami stanów magazynowych', 'STORE_LOGS', 'Dostęp do przeglądania logów stanów magazynowych ', '2024-11-29 18:24:11', '2024-11-29 18:24:11'),
(15, 'Zarządzanie wszystkimi uprawnieniami', 'ALL', 'Dostęp do wszystkich uprawnień', '2024-11-29 18:49:56', '2024-11-29 18:49:56');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `products`
--

DROP TABLE IF EXISTS `products`;
CREATE TABLE IF NOT EXISTS `products` (
  `product_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `vendor_id` bigint(20) UNSIGNED NOT NULL COMMENT 'Identyfikator producenta produktu',
  `parent_id` bigint(20) UNSIGNED DEFAULT NULL COMMENT 'Identyfikator produktu-rodzica',
  `product_name` varchar(100) DEFAULT NULL COMMENT 'Nazwa produktu',
  `product_description` text DEFAULT NULL COMMENT 'Długi opis produktu',
  `summary` text DEFAULT NULL COMMENT 'Krótki opis produktu',
  `cover_path` varchar(100) DEFAULT NULL COMMENT 'Ścieżka do pliku zdjęcia produktu',
  `net_price` int(11) DEFAULT NULL COMMENT 'Cena netto produktu',
  `tax_class` int(11) DEFAULT NULL COMMENT 'Stawka podatku VAT',
  `sku` varchar(100) DEFAULT NULL COMMENT 'Wartość jednostki magazynowania produktu',
  `type` enum('configurable','simple') NOT NULL COMMENT 'Typ produktu',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas dodania produktu',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Czas zaktualizowania produktu',
  `deleted_at` timestamp NULL DEFAULT NULL COMMENT 'Czas usunięcia produktu',
  PRIMARY KEY (`product_id`),
  UNIQUE KEY `sku_idx` (`sku`),
  KEY `vendor_fk` (`vendor_id`),
  KEY `parent_product_fk` (`parent_id`) USING BTREE
) ENGINE=InnoDB AUTO_INCREMENT=97 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Produkty sklepu';

--
-- Dumping data for table `products`
--

INSERT INTO `products` (`product_id`, `vendor_id`, `parent_id`, `product_name`, `product_description`, `summary`, `cover_path`, `net_price`, `tax_class`, `sku`, `type`, `created_at`, `updated_at`, `deleted_at`) VALUES
(1, 1, NULL, 'Adidas Ultraboost 22', 'Adidas Ultraboost 22 to wygodne i stylowe buty do biegania z amortyzacją Boost.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 17:26:47', NULL),
(2, 1, NULL, 'Adidas Originals Hoodie', 'Adidas Originals Hoodie to klasyczna bluza z kapturem z logiem Trefoil.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 17:33:03', NULL),
(3, 2, NULL, 'Nike Air Max 270', 'Nike Air Max 270 oferują wyjątkowy komfort i nowoczesny design z widoczną poduszką Air.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 18:55:18', NULL),
(4, 2, NULL, 'Nike Dri-FIT T-shirt', 'Koszulka Nike Dri-FIT zapewnia szybkie odprowadzanie wilgoci podczas aktywności fizycznej.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 18:57:44', NULL),
(5, 3, NULL, 'Puma Suede Classic', 'Puma Suede Classic to ponadczasowe sneakersy wykonane z wysokiej jakości zamszu.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 18:59:33', NULL),
(6, 3, NULL, 'Puma Training Shorts', 'Spodenki Puma Training Shorts idealne na trening, wykonane z lekkiego i oddychającego materiału.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:00:21', NULL),
(7, 4, NULL, 'Reebok Nano X3', 'Reebok Nano X3 to wszechstronne buty treningowe przeznaczone do crossfitu i innych aktywności.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:01:15', NULL),
(8, 4, NULL, 'Reebok Classic Leather', 'Reebok Classic Leather to stylowe sneakersy wykonane ze skóry naturalnej.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:02:18', NULL),
(9, 5, NULL, 'H&M Slim Fit Jeans', 'Slim Fit Jeans od H&M to wygodne dżinsy w nowoczesnym kroju.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:03:09', NULL),
(10, 5, NULL, 'H&M Oversized Hoodie', 'Bluza Oversized Hoodie od H&M łączy wygodę z luźnym krojem idealnym na co dzień.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:03:49', NULL),
(11, 6, NULL, 'Zara Satin Blouse', 'Zara Satin Blouse to elegancka bluzka satynowa idealna na formalne okazje.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:04:52', NULL),
(12, 6, NULL, 'Zara Knit Sweater', 'Zara Knit Sweater to ciepły i stylowy sweter idealny na chłodniejsze dni.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:05:33', NULL),
(13, 7, NULL, 'Levi\'s 501 Original Fit Jeans', 'Levi\'s 501 Original Fit Jeans to klasyczne dżinsy o prostym kroju.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:06:48', NULL),
(14, 7, NULL, 'Levi\'s Graphic Tee', 'Koszulka Levi\'s Graphic Tee to klasyczny t-shirt z logiem marki.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:09:07', NULL),
(15, 8, NULL, 'Tommy Hilfiger Polo Shirt', 'Tommy Hilfiger Polo Shirt to klasyczna koszulka polo z logo na piersi.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:10:00', NULL),
(16, 8, NULL, 'Tommy Hilfiger Hoodie', 'Bluza Tommy Hilfiger Hoodie łączy styl i komfort, idealna na co dzień.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:10:36', NULL),
(17, 9, NULL, 'Calvin Klein Modern Bralette', 'Calvin Klein Modern Bralette to minimalistyczny i wygodny biustonosz sportowy.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:11:30', NULL),
(18, 9, NULL, 'Calvin Klein Lounge Pants', 'Spodnie Calvin Klein Lounge Pants to idealna propozycja do noszenia w domu.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:12:25', NULL),
(19, 10, NULL, 'Gucci Ace Sneakers', 'Gucci Ace Sneakers to luksusowe buty sportowe wykonane z wysokiej jakości skóry.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:13:52', NULL),
(20, 10, NULL, 'Gucci GG Belt', 'Gucci GG Belt to klasyczny pasek z charakterystycznym logiem GG.', 'Klasyczny pasek Gucci', '/assets/images/product59.jpg', 210000, 23, 'GGB-020', 'simple', '2024-11-28 00:38:13', '2024-11-29 18:23:39', NULL),
(21, 11, NULL, 'Prada Re-Nylon Backpack', 'Plecak Prada Re-Nylon wykonany z recyklingowanego nylonu.', 'Plecak z recyklingowanego materiału', '/assets/images/product60.jpg', 490000, 23, 'PRNB-021', 'simple', '2024-11-28 00:38:13', '2024-11-29 18:23:45', NULL),
(22, 11, NULL, 'Prada Leather Loafers', 'Prada Leather Loafers to luksusowe mokasyny wykonane z najwyższej jakości skóry.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:14:42', NULL),
(23, 12, NULL, 'The North Face Nuptse Jacket', 'The North Face Nuptse Jacket to kultowa kurtka zimowa z doskonałą izolacją.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:15:32', NULL),
(24, 12, NULL, 'The North Face Base Camp Duffel', 'The North Face Base Camp Duffel to wytrzymała torba podróżna.', 'Wytrzymała torba podróżna', '/assets/images/product61.jpg', 65000, 23, 'TNFBCD-024', 'simple', '2024-11-28 00:38:13', '2024-11-29 18:23:59', NULL),
(25, 13, NULL, 'Columbia Bugaboo II Jacket', 'Columbia Bugaboo II Jacket to wodoodporna kurtka z podpinką.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:16:15', NULL),
(26, 13, NULL, 'Columbia Silver Ridge Pants', 'Spodnie Columbia Silver Ridge Pants idealne na górskie wyprawy.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:16:51', NULL),
(27, 14, NULL, 'Patagonia Better Sweater', 'Patagonia Better Sweater to wygodny polar wykonany z recyklingowanych materiałów.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:18:16', NULL),
(28, 14, NULL, 'Patagonia Torrentshell Jacket', 'Patagonia Torrentshell Jacket to lekka kurtka wodoodporna.', '', NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:49:07', '2024-11-29 19:19:19', NULL),
(29, 15, NULL, 'Mango Double-Breasted Blazer', 'Mango Double-Breasted Blazer to stylowa koszula na formalne okazje.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:20:00', NULL),
(30, 15, NULL, 'Mango Pleated Trousers', 'Spodnie Mango Pleated Trousers to elegancka propozycja do biura.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:21:24', NULL),
(31, 16, NULL, 'Uniqlo Heattech Shirt', 'Uniqlo Heattech Shirt to koszulka termoaktywna na chłodne dni.', '', NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:22:31', NULL),
(32, 16, NULL, 'Uniqlo Ultra Light Down Jacket', 'Kurtka Uniqlo Ultra Light Down Jacket to lekka, puchowa kurtka.', NULL, NULL, NULL, 23, NULL, 'configurable', '2024-11-28 00:38:13', '2024-11-29 19:23:44', NULL),
(33, 1, 1, NULL, NULL, 'Buty do biegania w paski z amortyzacją Boost - rozmiar 39', '/assets/images/product1.jpg', 45000, NULL, 'BSN-234', 'simple', '2024-11-28 22:10:53', '2024-11-29 17:27:00', NULL),
(34, 1, 1, NULL, NULL, 'Buty do biegania w paski z amortyzacją Boost - rozmiar 42', '/assets/images/product2.jpg', 45000, NULL, 'BSLR-234', 'simple', '2024-11-28 22:12:29', '2024-11-29 17:27:07', NULL),
(35, 1, 2, NULL, NULL, 'Czerwona klasyczna bluza z kapturem - rozmiar M', '/assets/images/product3.jpg', 25000, NULL, 'ADORH-002', 'simple', '2024-11-29 16:55:25', '2024-11-29 17:33:52', NULL),
(36, 1, 2, NULL, NULL, 'Czerwona klasyczna bluza z kapturem - rozmiar L', '/assets/images/product4.jpg', 25000, NULL, 'ADORH-003', 'simple', '2024-11-29 17:27:38', '2024-11-29 17:33:54', NULL),
(37, 2, 3, NULL, NULL, 'Stylowe gładkie sneakersy z widoczną poduszką Air - rozmiar 40', '/assets/images/product5.jpg', 55000, NULL, 'NAM270-003', 'simple', '2024-11-29 18:00:32', '2024-11-29 18:57:23', NULL),
(38, 2, 3, NULL, NULL, 'Stylowe gładkie sneakersy z widoczną poduszką Air - rozmiar 42', '/assets/images/product6.jpg', 55000, NULL, 'NAM270-004', 'simple', '2024-11-29 18:00:45', '2024-11-29 18:57:29', NULL),
(39, 2, 4, NULL, NULL, 'Koszulka wodoodporna treningowa Dri-FIT - rozmiar S', '/assets/images/product7.jpg', 12000, NULL, 'NDFTS-004', 'simple', '2024-11-29 18:01:15', '2024-11-29 18:58:32', NULL),
(40, 2, 4, NULL, NULL, 'Koszulka wodoodporna treningowa Dri-FIT - rozmiar M', '/assets/images/product8.jpg', 12000, NULL, 'NDFTS-005', 'simple', '2024-11-29 18:01:29', '2024-11-29 18:58:47', NULL),
(41, 3, 5, NULL, NULL, 'Zamszowe gładkie sneakersy o klasycznym kroju - rozmiar 41', '/assets/images/product9.jpg', 32000, NULL, 'PSC-005', 'simple', '2024-11-29 18:02:06', '2024-11-29 18:59:56', NULL),
(42, 3, 5, NULL, NULL, 'Zamszowe gładkie sneakersy o klasycznym kroju - rozmiar 42', '/assets/images/product10.jpg', 32000, NULL, 'PSC-006', 'simple', '2024-11-29 18:02:12', '2024-11-29 19:00:12', NULL),
(43, 3, 6, NULL, NULL, 'Błękitne spodenki treningowe z oddychającego materiału - rozmiar XL', '/assets/images/product11.jpg', 9000, NULL, 'PTS-006', 'simple', '2024-11-29 18:02:18', '2024-11-29 19:01:03', NULL),
(44, 3, 6, NULL, NULL, 'Błękitne spodenki treningowe z oddychającego materiału - rozmiar M', '/assets/images/product12.jpg', 9000, NULL, 'PTS-007', 'simple', '2024-11-29 18:02:23', '2024-11-29 19:01:08', NULL),
(45, 4, 7, NULL, NULL, 'Wszechstronne buty w paski treningowe - rozmiar 38', '/assets/images/product13.jpg', 39000, NULL, 'RNX3-007', 'simple', '2024-11-29 18:02:30', '2024-11-29 19:01:42', NULL),
(46, 4, 7, NULL, NULL, 'Wszechstronne buty w paski treningowe - rozmiar 41', '/assets/images/product14.jpg', 39000, NULL, 'RNX3-008', 'simple', '2024-11-29 18:02:38', '2024-11-29 19:02:09', NULL),
(47, 4, 8, NULL, NULL, 'Skórzane czerwone sneakersy o klasycznym wyglądzie - rozmiar 42', '/assets/images/product15.jpg', 28000, NULL, 'RCL-008', 'simple', '2024-11-29 18:02:46', '2024-11-29 19:02:50', NULL),
(48, 4, 8, NULL, NULL, 'Skórzane czerwone sneakersy o klasycznym wyglądzie - rozmiar 44', '/assets/images/product16.jpg', 28000, NULL, 'RCL-009', 'simple', '2024-11-29 18:03:08', '2024-11-29 19:03:00', NULL),
(49, 5, 9, NULL, NULL, 'Wygodne czarne dżinsy Slim Fit - rozmiar M', '/assets/images/product17.jpg', 13000, NULL, 'HMSFJ-009', 'simple', '2024-11-29 18:03:29', '2024-11-29 19:03:32', NULL),
(50, 5, 9, NULL, NULL, 'Wygodne czarne dżinsy Slim Fit - rozmiar L', '/assets/images/product18.jpg', 13000, NULL, 'HMSFJ-010', 'simple', '2024-11-29 18:03:35', '2024-11-29 19:03:42', NULL),
(51, 5, 10, NULL, NULL, 'Luźna bawełniana bluza oversize - rozmiar S', '/assets/images/product19.jpg', 11000, NULL, 'HMOVH-010', 'simple', '2024-11-29 18:03:46', '2024-11-29 19:04:29', NULL),
(52, 5, 10, NULL, NULL, 'Luźna bawełniana bluza oversize - rozmiar M', '/assets/images/product20.jpg', 11000, NULL, 'HMOVH-011', 'simple', '2024-11-29 18:03:53', '2024-11-29 19:04:41', NULL),
(53, 6, 11, NULL, NULL, 'Elegancka gładka bluzka satynowa - rozmiar S', '/assets/images/product21.jpg', 19000, NULL, 'ZSB-011', 'simple', '2024-11-29 18:04:01', '2024-11-29 19:05:16', NULL),
(54, 6, 11, NULL, NULL, 'Elegancka gładka bluzka satynowa - rozmiar M', '/assets/images/product22.jpg', 19000, NULL, 'ZSB-012', 'simple', '2024-11-29 18:04:07', '2024-11-29 19:05:24', NULL),
(55, 6, 12, NULL, NULL, 'Stylowy wełniany sweter z dzianiny - rozmiar M', '/assets/images/product23.jpg', 22000, NULL, 'ZKS-012', 'simple', '2024-11-29 18:04:16', '2024-11-29 19:05:57', NULL),
(56, 6, 12, NULL, NULL, 'Stylowy wełniany sweter z dzianiny - rozmiar L', '/assets/images/product24.jpg', 22000, NULL, 'ZKS-013', 'simple', '2024-11-29 18:04:29', '2024-11-29 19:06:07', NULL),
(57, 7, 13, NULL, NULL, 'Klasyczne granatowe dżinsy z prostą nogawką - rozmiar L', '/assets/images/product25.jpg', 35000, NULL, 'L501-013', 'simple', '2024-11-29 18:04:36', '2024-11-29 19:08:54', NULL),
(58, 7, 13, NULL, NULL, 'Klasyczne granatowe dżinsy z prostą nogawką - rozmiar XL', '/assets/images/product26.jpg', 35000, NULL, 'L501-014', 'simple', '2024-11-29 18:05:03', '2024-11-29 19:09:00', NULL),
(59, 7, 14, NULL, NULL, "T-shirt biały z logo marki Levi\'s - rozmiar M", '/assets/images/product27.jpg', 12000, NULL, 'LGT-014', 'simple', '2024-11-29 18:05:11', '2024-11-29 19:09:39', NULL),
(60, 7, 14, NULL, NULL, "T-shirt biały z logo marki Levi\'s - rozmiar L", '/assets/images/product28.jpg', 12000, NULL, 'LGT-015', 'simple', '2024-11-29 18:05:21', '2024-11-29 19:09:51', NULL),
(61, 8, 15, NULL, NULL, 'Klasyczna czarna koszulka polo - rozmiar L', '/assets/images/product29.jpg', 25000, NULL, 'THPS-015', 'simple', '2024-11-29 18:05:27', '2024-11-29 19:10:19', NULL),
(62, 8, 15, NULL, NULL, 'Klasyczna czarna koszulka polo - rozmiar XL', '/assets/images/product30.jpg', 25000, NULL, 'THPS-016', 'simple', '2024-11-29 18:05:33', '2024-11-29 19:10:29', NULL),
(63, 8, 16, NULL, NULL, 'Bluza czerwona z logiem Tommy Hilfiger - rozmiar S', '/assets/images/product31.jpg', 32000, NULL, 'THH-016', 'simple', '2024-11-29 18:05:41', '2024-11-29 19:11:03', NULL),
(64, 8, 16, NULL, NULL, 'Bluza czerwona z logiem Tommy Hilfiger - rozmiar M', '/assets/images/product32.jpg', 32000, NULL, 'THH-017', 'simple', '2024-11-29 18:05:50', '2024-11-29 19:11:14', NULL),
(65, 9, 17, NULL, NULL, 'Wygodny błękitny biustonosz sportowy - rozmiar 90cm', '/assets/images/product33.jpg', 15000, NULL, 'CKMB-017', 'simple', '2024-11-29 18:05:59', '2024-11-29 19:12:07', NULL),
(66, 9, 17, NULL, NULL, 'Wygodny błękitny biustonosz sportowy - rozmiar 95cm', '/assets/images/product34.jpg', 15000, NULL, 'CKMB-018', 'simple', '2024-11-29 18:06:27', '2024-11-29 19:12:13', NULL),
(67, 9, 18, NULL, NULL, 'Wygodne bawełniane spodnie do noszenia w domu - rozmiar S', '/assets/images/product35.jpg', 20000, NULL, 'CKLP-018', 'simple', '2024-11-29 18:06:36', '2024-11-29 19:12:52', NULL),
(68, 9, 18, NULL, NULL, 'Wygodne bawełniane spodnie do noszenia w domu - rozmiar  M', '/assets/images/product36.jpg', 20000, NULL, 'CKLP-019', 'simple', '2024-11-29 18:06:44', '2024-11-29 19:13:34', NULL),
(69, 10, 19, NULL, NULL, 'Luksusowe białe sneakersy ze skóry - rozmiar 40', '/assets/images/product37.jpg', 320000, NULL, 'GAS-019', 'simple', '2024-11-29 18:06:54', '2024-11-29 19:14:20', NULL),
(70, 10, 19, NULL, NULL, 'Luksusowe białe sneakersy ze skóry - rozmiar 42', '/assets/images/product38.jpg', 320000, NULL, 'GAS-020', 'simple', '2024-11-29 18:07:14', '2024-11-29 19:14:35', NULL),
(75, 11, 22, NULL, NULL, 'Luksusowe brązowe skórzane mokasyny - rozmiar 41', '/assets/images/product39.jpg', 350000, NULL, 'PLL-022', 'simple', '2024-11-29 18:07:46', '2024-11-29 19:15:14', NULL),
(76, 11, 22, NULL, NULL, 'Luksusowe brązowe skórzane mokasyny - rozmiar 44', '/assets/images/product40.jpg', 350000, NULL, 'PLL-023', 'simple', '2024-11-29 18:07:52', '2024-11-29 19:15:23', NULL),
(77, 12, 23, NULL, NULL, 'Ciepła zielona kurtka zimowa - rozmiar M', '/assets/images/product41.jpg', 140000, NULL, 'TNFNJ-023', 'simple', '2024-11-29 18:07:57', '2024-11-29 19:15:54', NULL),
(78, 12, 23, NULL, NULL, 'Ciepła zielona kurtka zimowa - rozmiar L', '/assets/images/product42.jpg', 140000, NULL, 'TNFNJ-024', 'simple', '2024-11-29 18:08:06', '2024-11-29 19:16:04', NULL),
(81, 13, 25, NULL, NULL, 'Wodoodporna czarna kurtka zimowa - rozmiar M', '/assets/images/product43.jpg', 80000, NULL, 'CBIIJ-025', 'simple', '2024-11-29 18:08:33', '2024-11-29 19:16:35', NULL),
(82, 13, 25, NULL, NULL, 'Wodoodporna czarna kurtka zimowa - rozmiar L', '/assets/images/product44.jpg', 80000, NULL, 'CBIIJ-026', 'simple', '2024-11-29 18:08:44', '2024-11-29 19:16:44', NULL),
(83, 13, 26, NULL, NULL, 'Lekkie bawełniane spodnie trekkingowe - rozmiar S', '/assets/images/product45.jpg', 30000, NULL, 'CSR-026', 'simple', '2024-11-29 18:08:55', '2024-11-29 19:17:15', NULL),
(84, 13, 26, NULL, NULL, 'Lekkie bawełniane spodnie trekkingowe - rozmiar L', '/assets/images/product46.jpg', 30000, NULL, 'CSR-027', 'simple', '2024-11-29 18:09:14', '2024-11-29 19:17:39', NULL),
(85, 14, 27, NULL, NULL, 'Polar gładki z recyklingowanych materiałów - rozmiar S', '/assets/images/product47.jpg', 45000, NULL, 'PBS-027', 'simple', '2024-11-29 18:09:26', '2024-11-29 19:19:02', NULL),
(86, 14, 27, NULL, NULL, 'Polar gładki z recyklingowanych materiałów - rozmiar M', '/assets/images/product48.jpg', 45000, NULL, 'PBS-028', 'simple', '2024-11-29 18:09:33', '2024-11-29 19:19:12', NULL),
(87, 14, 28, NULL, NULL, 'Lekka granatowa kurtka przeciwdeszczowa - rozmiar M', '/assets/images/product49.jpg', 65000, NULL, 'PTJ-028', 'simple', '2024-11-29 18:09:40', '2024-11-29 19:19:41', NULL),
(88, 14, 28, NULL, NULL, 'Lekka granatowa kurtka przeciwdeszczowa - rozmiar L', '/assets/images/product50.jpg', 65000, NULL, 'PTJ-029', 'simple', '2024-11-29 18:09:47', '2024-11-29 19:19:51', NULL),
(89, 15, 29, NULL, NULL, 'Stylowa wodoodporna koszula na formalne okazje - rozmiar S', '/assets/images/product51.jpg', 30000, NULL, 'MDBB-029', 'simple', '2024-11-29 18:10:00', '2024-11-29 19:20:55', NULL),
(90, 15, 29, NULL, NULL, 'Stylowa wodoodporna koszula na formalne okazje - rozmiar XL', '/assets/images/product52.jpg', 30000, NULL, 'MDBB-030', 'simple', '2024-11-29 18:10:07', '2024-11-29 19:21:12', NULL),
(91, 15, 30, NULL, NULL, 'Eleganckie spodnie z zakładkami i zamkiem błyskawicznym - rozmiar M', '/assets/images/product53.jpg', 20000, NULL, 'MPT-030', 'simple', '2024-11-29 18:10:16', '2024-11-29 19:22:10', NULL),
(92, 15, 30, NULL, NULL, 'Eleganckie spodnie z zakładkami i zamkiem błyskawicznym - rozmiar XL', '/assets/images/product54.jpg', 20000, NULL, 'MPT-031', 'simple', '2024-11-29 18:10:24', '2024-11-29 19:22:24', NULL),
(93, 16, 31, NULL, NULL, 'Koszulka termoaktywna gładka - rozmiar S', '/assets/images/product55.jpg', 12000, NULL, 'UHS-031', 'simple', '2024-11-29 18:10:29', '2024-11-29 19:23:20', NULL),
(94, 16, 31, NULL, NULL, 'Koszulka termoaktywna gładka - rozmiar M', '/assets/images/product56.jpg', 12000, NULL, 'UHS-032', 'simple', '2024-11-29 18:10:39', '2024-11-29 19:23:37', NULL),
(95, 16, 32, NULL, NULL, 'Lekka puchowa kurtka czerwona - rozmiar M', '/assets/images/product57.jpg', 40000, NULL, 'UULDJ-032', 'simple', '2024-11-29 18:10:49', '2024-11-29 19:24:01', NULL),
(96, 16, 32, NULL, NULL, 'Lekka puchowa kurtka czerwona - rozmiar L', '/assets/images/product58.jpg', 40000, NULL, 'UULDJ-033', 'simple', '2024-11-29 18:11:07', '2024-11-29 19:24:08', NULL);

--
-- Wyzwalacze `products`
--
DROP TRIGGER IF EXISTS `after_add_product`;
DELIMITER $$
CREATE TRIGGER `after_add_product` AFTER INSERT ON `products` FOR EACH ROW BEGIN
	IF NEW.type='simple' THEN
		INSERT INTO stock_events(product_id, event_type) 		 VALUES(NEW.product_id, 'snapshot');
    	END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `product_attribute`
--

DROP TABLE IF EXISTS `product_attribute`;
CREATE TABLE IF NOT EXISTS `product_attribute` (
  `product_attribute_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `attribute_id` bigint(20) UNSIGNED NOT NULL,
  `value` varchar(100) DEFAULT NULL COMMENT 'Wartość atrybutu produktu',
  PRIMARY KEY (`product_attribute_id`),
  KEY `product_fk2` (`product_id`),
  KEY `attribute_fk` (`attribute_id`)
) ENGINE=InnoDB AUTO_INCREMENT=129 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Tabela pivotowa łącząca produkt z atrybutem i jego wartością';

--
-- Dumping data for table `product_attribute`
--

INSERT INTO `product_attribute` (`product_attribute_id`, `product_id`, `attribute_id`, `value`) VALUES
(1, 1, 1, '39'),
(2, 1, 3, 'gładki'),
(3, 1, 1, '42'),
(4, 1, 3, 'w paski'),
(5, 2, 1, 'M'),
(6, 2, 2, 'czerwony'),
(7, 2, 1, 'L'),
(8, 2, 2, 'błękitny'),
(9, 3, 1, '40'),
(10, 3, 3, 'gładki'),
(11, 3, 1, '42'),
(12, 3, 3, 'w paski'),
(13, 4, 1, 'S'),
(14, 4, 10, 'wodoodporność'),
(15, 4, 1, 'M'),
(16, 4, 10, 'kieszenie'),
(17, 5, 1, '41'),
(18, 5, 3, 'gładki'),
(19, 5, 1, '42'),
(20, 5, 3, 'w paski'),
(21, 6, 1, 'XL'),
(22, 6, 2, 'czerwony'),
(23, 6, 1, 'M'),
(24, 6, 2, 'błękitny'),
(25, 7, 1, '38'),
(26, 7, 3, 'gładki'),
(27, 7, 1, '41'),
(28, 7, 3, 'w paski'),
(29, 8, 1, '42'),
(30, 8, 2, 'błękitny'),
(31, 8, 1, '44'),
(32, 8, 2, 'czerwony'),
(33, 9, 1, 'M'),
(34, 9, 2, 'czarny'),
(35, 9, 1, 'L'),
(36, 9, 2, 'szary'),
(37, 10, 1, 'S'),
(38, 10, 4, 'bawełna'),
(39, 10, 1, 'M'),
(40, 10, 4, 'poliester'),
(41, 11, 1, 'S'),
(42, 11, 3, 'gładki'),
(43, 11, 1, 'M'),
(44, 11, 3, 'w paski'),
(45, 12, 1, 'M'),
(46, 12, 4, 'wełna'),
(47, 12, 1, 'L'),
(48, 12, 4, 'kaszmir'),
(49, 13, 1, 'L'),
(50, 13, 2, 'czarny'),
(51, 13, 1, 'XL'),
(52, 13, 2, 'granatowy'),
(53, 14, 1, 'M'),
(54, 14, 2, 'biały'),
(55, 14, 1, 'L'),
(56, 14, 2, 'szary'),
(57, 15, 1, 'L'),
(58, 15, 2, 'czarny'),
(59, 15, 1, 'XL'),
(60, 15, 2, 'niebieski'),
(61, 16, 1, 'S'),
(62, 16, 2, 'czerwony'),
(63, 16, 1, 'M'),
(64, 16, 2, 'błękitny'),
(65, 17, 2, 'czerwony'),
(66, 17, 8, '90 cm'),
(67, 17, 2, 'błękitny'),
(68, 17, 8, '95 cm'),
(69, 18, 1, 'S'),
(70, 18, 4, 'bawełna'),
(71, 18, 1, 'M'),
(72, 18, 4, 'poliester'),
(73, 19, 1, '40'),
(74, 19, 2, 'czarny'),
(75, 19, 1, '42'),
(76, 19, 2, 'biały'),
(85, 22, 1, '41'),
(86, 22, 2, 'czarny'),
(87, 22, 1, '44'),
(88, 22, 2, 'brązowy'),
(89, 23, 1, 'M'),
(90, 23, 2, 'zielony'),
(91, 23, 1, 'L'),
(92, 23, 2, 'niebieski'),
(97, 25, 1, 'M'),
(98, 25, 2, 'szary'),
(99, 25, 1, 'L'),
(100, 25, 2, 'czarny'),
(101, 26, 1, 'S'),
(102, 26, 4, 'bawełna'),
(103, 26, 1, 'L'),
(104, 26, 4, 'poliester'),
(105, 27, 1, 'S'),
(106, 27, 3, 'gładki'),
(107, 27, 1, 'M'),
(108, 27, 3, 'w paski'),
(109, 28, 1, 'M'),
(110, 28, 2, 'granatowy'),
(111, 28, 1, 'L'),
(112, 28, 2, 'czarny'),
(113, 29, 1, 'L'),
(114, 29, 10, 'kieszenie'),
(115, 29, 1, 'XL'),
(116, 29, 10, 'wodoodporność'),
(117, 30, 1, 'M'),
(118, 30, 10, 'zapięcie magnetyczne'),
(119, 30, 1, 'XL'),
(120, 30, 10, 'zamek błyskawiczny'),
(121, 31, 1, 'S'),
(122, 31, 3, 'gładki'),
(123, 31, 1, 'M'),
(124, 31, 3, 'w paski'),
(125, 32, 1, 'M'),
(126, 32, 2, 'czerwony'),
(127, 32, 1, 'L'),
(128, 32, 2, 'niebieski');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `roles`
--

DROP TABLE IF EXISTS `roles`;
CREATE TABLE IF NOT EXISTS `roles` (
  `role_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `label` varchar(100) NOT NULL COMMENT 'Nazwa roli użytownika',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia roli użytkownika',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Czas aktualizacji roli użytkownika',
  PRIMARY KEY (`role_id`),
  UNIQUE KEY `role_label_index` (`label`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Role użytkownika';

--
-- Dumping data for table `roles`
--

INSERT INTO `roles` (`role_id`, `label`, `created_at`, `updated_at`) VALUES
(2, 'CUSTOMER_SERVICE_WORKER', '2024-11-18 20:25:01', '2024-11-18 20:25:01'),
(3, 'TECH_SUPPORT_WORKER', '2024-11-18 20:25:01', '2024-11-18 20:25:01'),
(4, 'DEV_READ', '2024-11-18 20:25:01', '2024-11-18 20:25:01'),
(5, 'DEV_WRITE', '2024-11-18 20:25:01', '2024-11-18 20:25:01'),
(6, 'ADMIN', '2024-11-18 20:25:01', '2024-11-18 20:25:01');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `role_permission`
--

DROP TABLE IF EXISTS `role_permission`;
CREATE TABLE IF NOT EXISTS `role_permission` (
  `role_permission_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `role_id` bigint(20) UNSIGNED NOT NULL,
  `permission_id` bigint(20) UNSIGNED NOT NULL,
  PRIMARY KEY (`role_permission_id`),
  KEY `permission_fk` (`permission_id`),
  KEY `role_fk` (`role_id`)
) ENGINE=InnoDB AUTO_INCREMENT=23 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Tabela pivotowa łącząca rolę z uprawnieniem';

--
-- Dumping data for table `role_permission`
--

INSERT INTO `role_permission` (`role_permission_id`, `role_id`, `permission_id`) VALUES
(2, 2, 3),
(3, 2, 1),
(4, 2, 2),
(5, 2, 4),
(6, 3, 3),
(7, 3, 1),
(8, 3, 14),
(9, 4, 8),
(10, 4, 7),
(11, 4, 4),
(12, 5, 10),
(13, 5, 9),
(14, 5, 6),
(15, 5, 5),
(16, 5, 12),
(17, 6, 15);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `role_user`
--

DROP TABLE IF EXISTS `role_user`;
CREATE TABLE IF NOT EXISTS `role_user` (
  `role_user_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `role_id` bigint(20) UNSIGNED NOT NULL,
  `user_id` bigint(20) UNSIGNED NOT NULL,
  PRIMARY KEY (`role_user_id`),
  KEY `role_fk2` (`role_id`),
  KEY `user_fk` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Tabela pivotowa łącząca rolę z użytkownikiem';

--
-- Dumping data for table `role_user`
--

INSERT INTO `role_user` (`role_user_id`, `role_id`, `user_id`) VALUES
(7, 2, 2),
(8, 2, 3),
(9, 2, 4),
(10, 2, 5),
(11, 3, 6),
(12, 3, 7),
(13, 4, 8),
(14, 4, 9),
(15, 5, 10),
(16, 2, 11),
(17, 3, 12),
(18, 2, 13),
(20, 3, 1),
(21, 2, 14),
(22, 2, 15),
(23, 2, 16),
(24, 2, 17),
(25, 2, 18);

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `shipping_details`
--

DROP TABLE IF EXISTS `shipping_details`;
CREATE TABLE IF NOT EXISTS `shipping_details` (
  `shipping_details_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'identyfikator wiersza',
  `shipper_provider_id` bigint(20) UNSIGNED NOT NULL,
  `first_name` varchar(100) NOT NULL COMMENT 'imię klienta',
  `last_name` varchar(100) NOT NULL COMMENT 'nazwisko klienta',
  `address_line_1` varchar(100) NOT NULL COMMENT 'pierwsza linia adresu klienta',
  `address_line_2` varchar(100) DEFAULT NULL COMMENT 'druga opcjonalna linia adresu klienta',
  `email` varchar(255) NOT NULL COMMENT 'adres email klienta',
  `country` char(2) NOT NULL COMMENT 'skrót kraju klienta',
  `city` varchar(255) NOT NULL COMMENT 'miasto klienta',
  `state` varchar(255) DEFAULT NULL COMMENT 'nazwa stanu klienta (dotyczy USA)',
  `postal_code` varchar(12) NOT NULL COMMENT 'kod pocztowy klienta',
  `phone_number` varchar(20) NOT NULL COMMENT 'numer telefonu klienta',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'czas utworzenia szczegółów wysyłki',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'czas aktualizacji szczegółów wysyłki',
  PRIMARY KEY (`shipping_details_id`),
  KEY `shipper_provider_fk` (`shipper_provider_id`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Szczegóły wysyłki';

--
-- Dumping data for table `shipping_details`
--

INSERT INTO `shipping_details` (`shipping_details_id`, `shipper_provider_id`, `first_name`, `last_name`, `address_line_1`, `address_line_2`, `email`, `country`, `city`, `state`, `postal_code`, `phone_number`, `created_at`, `updated_at`) VALUES
(1, 2, 'Helena', 'Baran', 'ul. Kolorowa 5/21', NULL, 'helena.baran@yahoo.com', 'PL', 'Nowy Sącz', NULL, '33-300', '(+48) 634837432', '2024-12-28 15:48:04', '2024-12-28 15:48:04'),
(2, 3, 'Adrianna', 'Zielińska', 'Stara Wieś 95', NULL, 'adrianna98@gmail.com', 'PL', 'Limanowa', NULL, '34-600', '(+48) 294645834', '2024-12-30 21:58:43', '2024-12-30 21:58:43'),
(4, 6, 'Marianna', 'Zawadzka', 'Morska 04A', NULL, 'marianna74@yahoo.com', 'PL', 'Stargard Szczeciński', NULL, '83-116', '(+48) 537347585', '2025-01-02 16:47:05', '2025-01-02 16:47:05'),
(5, 1, 'Paweł', 'Kozłowski', 'Sienkiewicza Henryka 63A/65', NULL, 'pawel74@gmail.com', 'PL', 'Kraśnik', NULL, '40-808', '(+48) 236290178', '2025-01-04 13:30:15', '2025-01-04 13:30:15'),
(6, 6, 'Róża', 'Witkowska', 'ul. Jodłowa 4/50', NULL, 'roza.witkowska@hotmail.com', 'PL', 'Konin', NULL, '53-200', '(+48) 723832123', '2025-01-04 14:12:41', '2025-01-04 14:13:08'),
(7, 6, 'Kacper', 'Gómulak', 'ul. Kolorowa 28', NULL, 'kacper.gomulak969@gmail.com', 'PL', 'Kraków', NULL, '31-366', '(+48) 764232234', '2025-01-05 08:27:22', '2025-01-05 08:27:22');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `shipping_providers`
--

DROP TABLE IF EXISTS `shipping_providers`;
CREATE TABLE IF NOT EXISTS `shipping_providers` (
  `shipper_provider_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `label` varchar(100) NOT NULL COMMENT 'Nazwa przewoźnika',
  `ident` varchar(100) NOT NULL COMMENT 'Identyfikator przewoźnika',
  `description` text NOT NULL COMMENT 'Opis przewoźnika',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia przewoźnika',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Czas zaktualizowania przewoźnika',
  PRIMARY KEY (`shipper_provider_id`),
  UNIQUE KEY `shipper_provider_label_idx` (`label`),
  UNIQUE KEY `shipper_provider_ident_idx` (`ident`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Przewoźnicy';

--
-- Dumping data for table `shipping_providers`
--

INSERT INTO `shipping_providers` (`shipper_provider_id`, `label`, `ident`, `description`, `created_at`, `updated_at`) VALUES
(1, 'DPD Polska', 'DPD', 'Międzynarodowy przewoźnik oferujący usługi kurierskie, przesyłki krajowe i międzynarodowe.', '2024-11-27 14:57:16', '2024-11-29 19:31:11'),
(2, 'InPost', 'INPOST', 'Polski operator logistyczny, znany z paczkomatów i przesyłek kurierskich.', '2024-11-27 14:57:16', '2024-11-29 19:31:12'),
(3, 'Poczta Polska', 'POCZTA_POLSKA', 'Narodowy operator pocztowy w Polsce, oferujący przesyłki listowe, kurierskie i międzynarodowe.', '2024-11-27 14:57:16', '2024-11-29 19:31:12'),
(4, 'GLS Poland', 'GLS', 'Przewoźnik logistyczny, specjalizujący się w przesyłkach krajowych i międzynarodowych.', '2024-11-27 14:57:16', '2024-11-29 19:31:12'),
(5, 'DHL Parcel Polska', 'DHL', 'Światowy lider w branży kurierskiej, oferujący przesyłki ekspresowe i logistykę e-commerce.', '2024-11-27 14:57:16', '2024-11-29 19:31:12'),
(6, 'FedEx', 'FEDEX', 'Międzynarodowy dostawca usług kurierskich i transportowych, oferujący szybkie przesyłki.', '2024-11-27 14:57:16', '2024-11-29 19:31:12'),
(7, 'UPS Polska', 'UPS', 'Globalny lider usług kurierskich i logistycznych, specjalizujący się w przesyłkach ekspresowych.', '2024-11-27 14:57:16', '2024-11-29 19:31:12'),
(8, 'Paczka w RUCHu', 'RUCH', 'Usługa odbioru przesyłek w kioskach i punktach RUCHu, popularna w Polsce.', '2024-11-27 14:57:16', '2024-11-29 19:31:13');

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `stock_events`
--

DROP TABLE IF EXISTS `stock_events`;
CREATE TABLE IF NOT EXISTS `stock_events` (
  `stock_event_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `product_id` bigint(20) UNSIGNED NOT NULL,
  `order_id` bigint(20) UNSIGNED DEFAULT NULL,
  `diff` int(11) NOT NULL DEFAULT 0 COMMENT 'Różnica w stanie magazynowym',
  `event_type` enum('snapshot','stock_increased','stock_decreased','order_placed','order_cancelled','order_dispatched','returned') NOT NULL COMMENT 'Nazwa zdarzenia',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia zdarzenia',
  PRIMARY KEY (`stock_event_id`),
  KEY `product_fk3` (`product_id`),
  KEY `order_fk` (`order_id`)
) ENGINE=InnoDB AUTO_INCREMENT=87 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Dziennik zdarzeń aktualizacji stanu magazynowego';

--
-- Dumping data for table `stock_events`
--

INSERT INTO `stock_events` (`stock_event_id`, `product_id`, `order_id`, `diff`, `event_type`, `created_at`) VALUES
(1, 20, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(2, 21, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(3, 24, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(4, 33, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(5, 34, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(6, 35, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(7, 36, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(8, 37, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(9, 38, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(10, 39, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(11, 40, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(12, 41, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(13, 42, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(14, 43, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(15, 44, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(16, 45, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(17, 46, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(18, 47, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(19, 48, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(20, 49, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(21, 50, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(22, 51, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(23, 52, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(24, 53, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(25, 54, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(26, 55, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(27, 56, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(28, 57, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(29, 58, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(30, 59, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(31, 60, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(32, 61, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(33, 62, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(34, 63, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(35, 64, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(36, 65, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(37, 66, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(38, 67, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(39, 68, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(40, 69, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(41, 70, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(42, 75, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(43, 76, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(44, 77, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(45, 78, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(46, 81, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(47, 82, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(48, 83, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(49, 84, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(50, 85, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(51, 86, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(52, 87, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(53, 88, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(54, 89, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(55, 90, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(56, 91, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(57, 92, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(58, 93, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(59, 94, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(60, 95, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(61, 96, NULL, 0, 'snapshot', '2024-12-24 14:21:50'),
(62, 36, NULL, 100, 'stock_increased', '2024-12-27 15:03:13'),
(63, 40, NULL, 100, 'stock_increased', '2024-12-27 15:03:13'),
(64, 36, 1, -3, 'order_placed', '2024-12-28 19:07:31'),
(65, 40, 1, -2, 'order_placed', '2024-12-28 19:07:31'),
(66, 20, NULL, 100, 'stock_increased', '2024-12-30 20:39:14'),
(67, 36, 2, -5, 'order_placed', '2024-12-30 21:58:43'),
(68, 50, NULL, 100, 'stock_increased', '2025-01-02 16:45:25'),
(69, 50, 3, -3, 'order_placed', '2025-01-02 16:47:05'),
(70, 36, 1, -3, 'order_dispatched', '2025-01-02 18:34:27'),
(71, 40, 1, -2, 'order_dispatched', '2025-01-02 18:34:27'),
(72, 36, 2, 5, 'order_cancelled', '2025-01-02 19:29:14'),
(73, 50, 3, -3, 'order_dispatched', '2025-01-02 20:23:35'),
(74, 50, 3, 3, 'returned', '2025-01-02 20:24:58'),
(75, 50, 4, -1, 'order_placed', '2025-01-04 13:30:15'),
(76, 33, NULL, 100, 'stock_increased', '2025-01-04 13:47:22'),
(83, 33, 5, -2, 'order_placed', '2025-01-04 16:27:41'),
(84, 20, 6, -1, 'order_placed', '2025-01-05 08:27:22'),
(85, 20, 6, -1, 'order_dispatched', '2025-01-05 08:36:17'),
(86, 20, 6, 1, 'returned', '2025-01-05 08:39:57');

--
-- Wyzwalacze `stock_events`
--
DROP TRIGGER IF EXISTS `before_insert_stock_event`;
DELIMITER $$
CREATE TRIGGER `before_insert_stock_event` BEFORE INSERT ON `stock_events` FOR EACH ROW BEGIN
	-- Sprawdzamy, czy produkt jest typu 'simple'
    IF (SELECT type FROM products WHERE product_id = NEW.product_id) = 'configurable' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = "Nie można dodać produktu typu 'configurable'!";
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `users`
--

DROP TABLE IF EXISTS `users`;
CREATE TABLE IF NOT EXISTS `users` (
  `users_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `first_name` varchar(100) NOT NULL COMMENT 'Imię użytkownika bazy',
  `last_name` varchar(100) NOT NULL COMMENT 'Nazwisko użytkownika bazy',
  `email` varchar(255) NOT NULL COMMENT 'Email użytkownika bazy',
  `password` varchar(64) NOT NULL COMMENT 'Hasło użytkownika bazy',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia użytkownika',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Czas zaktualizowania użytkownika',
  PRIMARY KEY (`users_id`),
  UNIQUE KEY `user_email_index` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Użytkownicy bazy';

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`users_id`, `first_name`, `last_name`, `email`, `password`, `created_at`, `updated_at`) VALUES
(1, 'Karina', 'Szymańska', 'karina.szymanska@gmail.com', '95f53dea94d927af64755633d223946afd500810b30cb71de3d44b8edaa59040', '2024-11-26 22:06:18', '2024-11-26 22:06:18'),
(2, 'Kornel', 'Szulc', 'kornel.szulc123@gmail.com', '95bbc831bd8f96a3e7042e6da8e8ad45b63db0bee587500fed3eda0960f5d4d1', '2024-11-26 22:06:18', '2024-11-26 22:06:18'),
(3, 'Adrianna', 'Wojciechowska', 'ada.wojciechowska@gmail.com', '50ebc91b35b8bbc08e80d2488f55e6c29438806f83f4d6ff0e14dcd0143510fa', '2024-11-26 22:06:18', '2024-11-26 22:06:18'),
(4, 'Jacek', 'Szulc', 'jack.szulc345@gmail.com', '2a18c4b747ddc57ae267f81709473bac4d3fcef623e85014a0ecd98bb19ae699', '2024-11-26 22:06:18', '2024-11-26 22:06:18'),
(5, 'Juliusz', 'Jankowski', 'julek.jankowski@gmail.com', '9e7fb5c3a82f5de6671e911c06bcfdde2d35b83945b3aeb82cdd08eb28187ae0', '2024-11-26 22:06:18', '2024-11-26 22:06:18'),
(6, 'Martyna', 'Głowacka', 'martyna.glowacka450@gmail.com', 'f0bd8a7544c2c9a4abeca38ce8c4bc6bc03ab627fbb349deec76caa5213e4590', '2024-11-26 22:06:18', '2024-11-26 22:06:18'),
(7, 'Fabian', 'Czerwiński', 'fabian.czerwinki584@gmail.com', 'c11ba2bef71eb0e2ed99368e57098964eda78b44e9536c52cf5b09efcf0da5ba', '2024-11-26 22:06:18', '2024-11-26 22:06:18'),
(8, 'Olga', 'Szewczyk', 'olga.szewczyk342@gmail.com', 'd3cecdb060a574ab5e9d56a65e30d2cc9919f22ed61d619faae39950f48e5b44', '2024-11-26 22:06:18', '2024-11-26 22:06:18'),
(9, 'Elżbieta', 'Czarnecka', 'ela.czarnecka00@gmail.com', 'a98c2ca5f111d930fce005e6c093282d4e307d8f7873f94b8f4dac8c4d549c20', '2024-11-26 22:06:18', '2024-11-26 22:06:18'),
(10, 'Anita', 'Majewska', 'anita.majewska200@gmail.com', '2565cc2bde0288864b10e6973057537b826c236e2f34b777271b45b7d7aefb66', '2024-11-26 22:06:18', '2024-11-26 22:06:18'),
(11, 'Krzysztof', 'Kądziołka', 'krzysztof.kadziolka2091@gmail.com', '71d53b733d151d9907e347e40d8e40af1813aa2921b2acae902dba868b7ed09b', '2024-12-09 21:23:57', '2024-12-09 21:27:33'),
(12, 'Michał', 'Gomułka', 'michal.gomulka5980@gmail.com', '72a2963ac97bd36ba5a9bd93473e63bcf2425fbb5016b3674e1b88b2d36b2a5d', '2024-12-09 22:24:06', '2024-12-09 22:24:06'),
(13, 'Kamil', 'Musiał', 'kamil.musial5780@gmail.com', 'dcc3e5579943a0dadf42b71bece40183511cf4c16b92d8d45964f444284f599e', '2024-12-17 21:49:58', '2024-12-17 21:49:58'),
(14, 'Monika', 'Gryna', 'monika.gryna4453@gmail.com', 'c509e8864e6c14d29b10424c57b6dbada7d8e1ab1a00eac30616cc054cd2bfe7', '2024-12-27 12:57:52', '2024-12-27 12:57:52'),
(15, 'Monika', 'Gryna', 'monika.gryna9577@gmail.com', '1a6ae4ca12a61e332e2c51a1e693bd61b5869c7b3976a744e620e7dd5b5a0b11', '2024-12-27 13:00:49', '2024-12-27 13:00:49'),
(16, 'Anna', 'Nowak', 'anna.nowak9999@gmail.com', '433472dac456a1332621c2940a8bcc0bc1c89192d2f6bb083a3d27a99c1f3506', '2024-12-27 13:03:31', '2024-12-27 13:03:31'),
(17, 'Urszula', 'Wątroba', 'urszula.watroba3611@gmail.com', 'c8777a16d8d42a0b0c9ad380a5e1275fb1c78a2b0e0f98ccdb47884c048a8b04', '2024-12-27 13:05:48', '2024-12-27 13:05:48'),
(18, 'Kacper', 'Gómulak', 'kacper.gomulak4481@gmail.com', '7bbe61a97c24271ab27531f00266f6ecfae697a6dfaa69086f446f3702da1765', '2025-01-05 07:45:35', '2025-01-05 07:45:35');

--
-- Wyzwalacze `users`
--
DROP TRIGGER IF EXISTS `assign_user_role`;
DELIMITER $$
CREATE TRIGGER `assign_user_role` AFTER INSERT ON `users` FOR EACH ROW BEGIN

INSERT role_user VALUES(NULL, 2, NEW.users_id);

END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Struktura tabeli dla tabeli `vendors`
--

DROP TABLE IF EXISTS `vendors`;
CREATE TABLE IF NOT EXISTS `vendors` (
  `vendor_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'Identyfikator wiersza',
  `label` varchar(100) NOT NULL COMMENT 'Nazwa producenta ',
  `ident` varchar(100) NOT NULL COMMENT 'Identyfikator producenta (niezmienny)',
  `description` text NOT NULL COMMENT 'Opis producenta',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp() COMMENT 'Czas utworzenia producenta',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Czas zaktualizowania producenta',
  PRIMARY KEY (`vendor_id`),
  UNIQUE KEY `vendor_label_idx` (`label`),
  UNIQUE KEY `vendor_ident_idx` (`ident`)
) ENGINE=InnoDB AUTO_INCREMENT=17 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Producenci produktów';

--
-- Dumping data for table `vendors`
--

INSERT INTO `vendors` (`vendor_id`, `label`, `ident`, `description`, `created_at`, `updated_at`) VALUES
(1, 'Adidas', 'ADIDAS', 'Adidas AG to niemiecka firma zajmująca się produkcją odzieży i obuwia sportowego.', '2024-11-27 13:51:44', '2025-01-02 15:52:13'),
(2, 'Nike', 'NIKE', 'Nike Inc. to amerykański producent obuwia, odzieży sportowej i akcesoriów.', '2024-11-27 13:51:44', '2025-01-02 15:52:22'),
(3, 'Puma', 'PUMA', 'Puma SE to niemiecka firma projektująca i produkująca obuwie sportowe oraz odzież.', '2024-11-27 13:51:44', '2025-01-02 15:52:27'),
(4, 'Reebok', 'REEBOK', 'Reebok International Ltd. to brytyjsko-amerykańska firma produkująca obuwie i odzież sportową.', '2024-11-27 13:51:44', '2025-01-02 15:52:41'),
(5, 'H&M', 'H&M', 'H&M Hennes & Mauritz AB to szwedzka sieć odzieżowa oferująca ubrania w przystępnych cenach.', '2024-11-27 13:51:44', '2025-01-02 15:52:54'),
(6, 'Zara', 'ZARA', 'Zara SA to hiszpańska sieć odzieżowa będąca częścią grupy Inditex.', '2024-11-27 13:51:44', '2025-01-02 15:53:02'),
(7, "Levi\'s", 'LEVI_S', 'Levi Strauss & Co. to amerykańska firma znana głównie z produkcji dżinsów.', '2024-11-27 13:51:44', '2025-01-02 15:53:26'),
(8, 'Tommy', 'TOMMY_HILFIGER', 'Tommy Hilfiger to globalna marka oferująca odzież i obuwie o wysokiej jakości.', '2024-11-27 13:51:44', '2025-01-02 15:53:51'),
(9, 'Calvin Klein', 'CALVIN_KLEIN', 'Calvin Klein Inc. to amerykańska marka znana z minimalistycznych projektów i bielizny.', '2024-11-27 13:51:44', '2025-01-02 15:54:06'),
(10, 'Gucci', 'GUCCI', 'Gucci S.p.A. to włoska marka luksusowej odzieży, obuwia i akcesoriów.', '2024-11-27 13:51:44', '2025-01-02 15:54:12'),
(11, 'Prada', 'PRADA', 'Prada S.p.A. to włoska marka modowa oferująca luksusową odzież i akcesoria.', '2024-11-27 13:51:44', '2025-01-02 15:54:18'),
(12, 'The North Face', 'NORTH_FACE', 'The North Face, Inc. to amerykańska firma produkująca odzież i sprzęt outdoorowy.', '2024-11-27 13:51:44', '2025-01-02 15:54:54'),
(13, 'Columbia', 'COLUMBIA', 'Columbia Sportswear Company to amerykański producent odzieży i sprzętu outdoorowego.', '2024-11-27 13:51:44', '2025-01-02 15:55:04'),
(14, 'Patagonia', 'PATAGONIA', 'Patagonia, Inc. to amerykańska firma oferująca odzież i akcesoria outdoorowe.', '2024-11-27 13:51:44', '2025-01-02 15:55:12'),
(15, 'Mango', 'MANGO', 'Mango to hiszpańska marka odzieżowa oferująca stylowe i przystępne ubrania.', '2024-11-27 13:51:44', '2025-01-02 15:55:17'),
(16, 'Uniqlo', 'UNIQLO', 'Uniqlo to japońska sieć odzieżowa znana z minimalistycznych projektów.', '2024-11-27 13:51:44', '2025-01-02 15:55:24');

-- --------------------------------------------------------

--
-- Zastąpiona struktura widoku `v_categories_tree`
-- (See below for the actual view)
--
DROP VIEW IF EXISTS `v_categories_tree`;
CREATE TABLE IF NOT EXISTS `v_categories_tree` (
`lev1` varchar(255)
,`lev2` varchar(255)
,`lev3` varchar(255)
,`lev4` varchar(255)
,`lev5` varchar(255)
);

-- --------------------------------------------------------

--
-- Zastąpiona struktura widoku `v_customer_orders`
-- (See below for the actual view)
--
DROP VIEW IF EXISTS `v_customer_orders`;
CREATE TABLE IF NOT EXISTS `v_customer_orders` (
`CustomerName` varchar(100)
,`CustomerSurname` varchar(100)
,`OrderID` bigint(20) unsigned
,`OrderStatus` enum('placed','paid','ready_to_ship','shipped')
,`OrderCreateTime` timestamp
,`OrderUpdateTime` timestamp
);

-- --------------------------------------------------------

--
-- Zastąpiona struktura widoku `v_inventory`
-- (See below for the actual view)
--
DROP VIEW IF EXISTS `v_inventory`;
CREATE TABLE IF NOT EXISTS `v_inventory` (
`product_id` bigint(20) unsigned
,`product_name` varchar(100)
,`short_description` text
,`sellable_quantity` decimal(32,0)
,`storage_quantity` decimal(32,0)
);

-- --------------------------------------------------------

--
-- Zastąpiona struktura widoku `v_order_details`
-- (See below for the actual view)
--
DROP VIEW IF EXISTS `v_order_details`;
CREATE TABLE IF NOT EXISTS `v_order_details` (
`OrderID` bigint(20) unsigned
,`ProductSKU` varchar(100)
,`Quantity` int(11)
,`UnitPrice` decimal(13,2)
,`TotalCost` decimal(23,2)
);

-- --------------------------------------------------------

--
-- Zastąpiona struktura widoku `v_permission_IDs`
-- (See below for the actual view)
--
DROP VIEW IF EXISTS `v_permission_IDs`;
CREATE TABLE IF NOT EXISTS `v_permission_IDs` (
`permission_id` bigint(20) unsigned
,`identyfikator_uprawnienia` varchar(100)
);

-- --------------------------------------------------------

--
-- Zastąpiona struktura widoku `v_product_details`
-- (See below for the actual view)
--
DROP VIEW IF EXISTS `v_product_details`;
CREATE TABLE IF NOT EXISTS `v_product_details` (
`product_id` bigint(20) unsigned
,`product_name` varchar(100)
,`net_price` decimal(13,2)
,`gross_price` decimal(25,2)
,`sku` varchar(100)
,`type` varchar(12)
);

-- --------------------------------------------------------

--
-- Zastąpiona struktura widoku `v_role_IDs`
-- (See below for the actual view)
--
DROP VIEW IF EXISTS `v_role_IDs`;
CREATE TABLE IF NOT EXISTS `v_role_IDs` (
`role_id` bigint(20) unsigned
,`label` varchar(100)
);

-- --------------------------------------------------------

--
-- Zastąpiona struktura widoku `v_user_IDs`
-- (See below for the actual view)
--
DROP VIEW IF EXISTS `v_user_IDs`;
CREATE TABLE IF NOT EXISTS `v_user_IDs` (
`users_id` bigint(20) unsigned
,`first_name` varchar(100)
,`last_name` varchar(100)
);

-- --------------------------------------------------------

--
-- Struktura widoku `v_categories_tree`
--
DROP TABLE IF EXISTS `v_categories_tree`;

DROP VIEW IF EXISTS `v_categories_tree`;
CREATE OR REPLACE ALGORITHM=UNDEFINED DEFINER=`judka_damian`@`%` SQL SECURITY DEFINER VIEW `v_categories_tree`  AS SELECT `c1`.`category_name` AS `lev1`, `c2`.`category_name` AS `lev2`, `c3`.`category_name` AS `lev3`, `c4`.`category_name` AS `lev4`, `c5`.`category_name` AS `lev5` FROM ((((`categories` `c1` left join `categories` `c2` on(`c2`.`parent_id` = `c1`.`category_id`)) left join `categories` `c3` on(`c3`.`parent_id` = `c2`.`category_id`)) left join `categories` `c4` on(`c4`.`parent_id` = `c3`.`category_id`)) left join `categories` `c5` on(`c5`.`parent_id` = `c4`.`category_id`)) WHERE `c1`.`category_name` = 'Zakupy' ;

-- --------------------------------------------------------

--
-- Struktura widoku `v_customer_orders`
--
DROP TABLE IF EXISTS `v_customer_orders`;

DROP VIEW IF EXISTS `v_customer_orders`;
CREATE OR REPLACE ALGORITHM=UNDEFINED DEFINER=`judka_damian`@`%` SQL SECURITY DEFINER VIEW `v_customer_orders`  AS SELECT `c`.`first_name` AS `CustomerName`, `c`.`last_name` AS `CustomerSurname`, `o`.`order_id` AS `OrderID`, `o`.`status` AS `OrderStatus`, `o`.`created_at` AS `OrderCreateTime`, `o`.`updated_at` AS `OrderUpdateTime` FROM (`customers` `c` left join `orders` `o` on(`o`.`customer_id` = `c`.`customer_id`)) ORDER BY `o`.`updated_at` DESC ;

-- --------------------------------------------------------

--
-- Struktura widoku `v_inventory`
--
DROP TABLE IF EXISTS `v_inventory`;

DROP VIEW IF EXISTS `v_inventory`;
CREATE OR REPLACE ALGORITHM=UNDEFINED DEFINER=`judka_damian`@`%` SQL SECURITY DEFINER VIEW `v_inventory`  AS SELECT `se`.`product_id` AS `product_id`, `p`.`product_name` AS `product_name`, `p`.`summary` AS `short_description`, (select ifnull(sum(`se_inner`.`diff`),0) AS `sellable_quantity` from `stock_events` `se_inner` where `se_inner`.`event_type` in ('stock_increased','stock_decreased','order_placed','order_cancelled','returned') and `se_inner`.`product_id` = `se`.`product_id`) AS `sellable_quantity`, (select ifnull(sum(`se_inner`.`diff`),0) AS `sellable_quantity` from `stock_events` `se_inner` where `se_inner`.`event_type` in ('stock_increased','stock_decreased','order_dispatched','returned') and `se_inner`.`product_id` = `se`.`product_id`) AS `storage_quantity` FROM (`stock_events` `se` join `products` `p` on(`p`.`product_id` = `se`.`product_id`)) GROUP BY `p`.`product_id` ORDER BY `se`.`created_at` ASC ;

-- --------------------------------------------------------

--
-- Struktura widoku `v_order_details`
--
DROP TABLE IF EXISTS `v_order_details`;

DROP VIEW IF EXISTS `v_order_details`;
CREATE OR REPLACE ALGORITHM=UNDEFINED DEFINER=`judka_damian`@`%` SQL SECURITY DEFINER VIEW `v_order_details`  AS SELECT `o`.`order_id` AS `OrderID`, `vp`.`sku` AS `ProductSKU`, `ci`.`quantity` AS `Quantity`, `vp`.`net_price` AS `UnitPrice`, `vp`.`net_price`* `ci`.`quantity` AS `TotalCost` FROM (((`orders` `o` left join `cart` `ca` on(`o`.`cart_id` = `ca`.`cart_id`)) left join `cart_item` `ci` on(`ci`.`cart_id` = `ca`.`cart_id`)) join `v_product_details` `vp` on(`ci`.`product_id` = `vp`.`product_id`)) ORDER BY `o`.`updated_at` DESC ;

-- --------------------------------------------------------

--
-- Struktura widoku `v_permission_IDs`
--
DROP TABLE IF EXISTS `v_permission_IDs`;

DROP VIEW IF EXISTS `v_permission_IDs`;
CREATE OR REPLACE ALGORITHM=UNDEFINED DEFINER=`judka_damian`@`%` SQL SECURITY DEFINER VIEW `v_permission_IDs`  AS SELECT `permissions`.`permission_id` AS `permission_id`, `permissions`.`ident` AS `identyfikator_uprawnienia` FROM `permissions` ORDER BY `permissions`.`permission_id` ASC;

-- --------------------------------------------------------

--
-- Struktura widoku `v_product_details`
--
DROP TABLE IF EXISTS `v_product_details`;

DROP VIEW IF EXISTS `v_product_details`;
CREATE OR REPLACE ALGORITHM=UNDEFINED DEFINER=`judka_damian`@`%` SQL SECURITY DEFINER VIEW `v_product_details`  AS SELECT `p`.`product_id` AS `product_id`, `p2`.`product_name` AS `product_name`, round(`p`.`net_price` / 100,2) AS `net_price`, round(`p`.`net_price` * (1 + 0.01 * `p2`.`tax_class`) / 100,2) AS `gross_price`, `p`.`sku` AS `sku`, `p`.`type` AS `type` FROM (`products` `p2` left join `products` `p` on(`p`.`parent_id` = `p2`.`product_id`)) WHERE `p`.`type` = 'simple'union select `products`.`product_id` AS `product_id`,`products`.`product_name` AS `product_name`,round(`products`.`net_price` / 100,2) AS `net_price`,round(`products`.`net_price` * (1 + 0.01 * `products`.`tax_class`) / 100,2) AS `gross_price`,`products`.`sku` AS `sku`,`products`.`type` AS `type` from `products` where `products`.`type` = 'simple' and `products`.`product_name` is not null order by `product_id`  ;

-- --------------------------------------------------------

--
-- Struktura widoku `v_role_IDs`
--
DROP TABLE IF EXISTS `v_role_IDs`;

DROP VIEW IF EXISTS `v_role_IDs`;
CREATE OR REPLACE ALGORITHM=UNDEFINED DEFINER=`gumulak_kacper`@`%` SQL SECURITY DEFINER VIEW `v_role_IDs`  AS SELECT `roles`.`role_id` AS `role_id`, `roles`.`label` AS `label` FROM `roles` ORDER BY `roles`.`role_id` ASC ;

-- --------------------------------------------------------

--
-- Struktura widoku `v_user_IDs`
--
DROP TABLE IF EXISTS `v_user_IDs`;

DROP VIEW IF EXISTS `v_user_IDs`;
CREATE OR REPLACE ALGORITHM=UNDEFINED DEFINER=`gumulak_kacper`@`%` SQL SECURITY DEFINER VIEW `v_user_IDs`  AS SELECT `users`.`users_id` AS `users_id`, `users`.`first_name` AS `first_name`, `users`.`last_name` AS `last_name` FROM `users` ;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `addresses`
--
ALTER TABLE `addresses`
  ADD CONSTRAINT `customer_fk` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`);

--
-- Constraints for table `billing_details`
--
ALTER TABLE `billing_details`
  ADD CONSTRAINT `billing_provider_fk` FOREIGN KEY (`payment_provider_id`) REFERENCES `payment_providers` (`payment_provider_id`);

--
-- Constraints for table `cart`
--
ALTER TABLE `cart`
  ADD CONSTRAINT `billing_details_fk` FOREIGN KEY (`billing_details_id`) REFERENCES `billing_details` (`billing_details_id`),
  ADD CONSTRAINT `customer_fk2` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  ADD CONSTRAINT `shipping_details_fk` FOREIGN KEY (`shipping_details_id`) REFERENCES `shipping_details` (`shipping_details_id`);

--
-- Constraints for table `cart_item`
--
ALTER TABLE `cart_item`
  ADD CONSTRAINT `cart_fk` FOREIGN KEY (`cart_id`) REFERENCES `cart` (`cart_id`),
  ADD CONSTRAINT `product_fk4` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`);

--
-- Constraints for table `categories`
--
ALTER TABLE `categories`
  ADD CONSTRAINT `parent_category_fk` FOREIGN KEY (`parent_id`) REFERENCES `categories` (`category_id`);

--
-- Constraints for table `category_product`
--
ALTER TABLE `category_product`
  ADD CONSTRAINT `category_fk` FOREIGN KEY (`category_id`) REFERENCES `categories` (`category_id`),
  ADD CONSTRAINT `product_fk` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`);

--
-- Constraints for table `invoices`
--
ALTER TABLE `invoices`
  ADD CONSTRAINT `order_fk2` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`);

--
-- Constraints for table `invoice_lines`
--
ALTER TABLE `invoice_lines`
  ADD CONSTRAINT `invoice_fk` FOREIGN KEY (`invoice_id`) REFERENCES `invoices` (`invoice_id`),
  ADD CONSTRAINT `product_fk5` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`);

--
-- Constraints for table `login_history`
--
ALTER TABLE `login_history`
  ADD CONSTRAINT `customer_fk4` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`),
  ADD CONSTRAINT `user_fk2` FOREIGN KEY (`user_id`) REFERENCES `users` (`users_id`);

--
-- Constraints for table `orders`
--
ALTER TABLE `orders`
  ADD CONSTRAINT `cart_fk2` FOREIGN KEY (`cart_id`) REFERENCES `cart` (`cart_id`),
  ADD CONSTRAINT `customer_fk3` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`customer_id`);

--
-- Constraints for table `products`
--
ALTER TABLE `products`
  ADD CONSTRAINT `parent_product_fk` FOREIGN KEY (`parent_id`) REFERENCES `products` (`product_id`),
  ADD CONSTRAINT `vendor_fk` FOREIGN KEY (`vendor_id`) REFERENCES `vendors` (`vendor_id`);

--
-- Constraints for table `product_attribute`
--
ALTER TABLE `product_attribute`
  ADD CONSTRAINT `attribute_fk` FOREIGN KEY (`attribute_id`) REFERENCES `attributes` (`attribute_id`),
  ADD CONSTRAINT `product_fk2` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`);

--
-- Constraints for table `role_permission`
--
ALTER TABLE `role_permission`
  ADD CONSTRAINT `permission_fk` FOREIGN KEY (`permission_id`) REFERENCES `permissions` (`permission_id`),
  ADD CONSTRAINT `role_fk` FOREIGN KEY (`role_id`) REFERENCES `roles` (`role_id`);

--
-- Constraints for table `role_user`
--
ALTER TABLE `role_user`
  ADD CONSTRAINT `role_fk2` FOREIGN KEY (`role_id`) REFERENCES `roles` (`role_id`),
  ADD CONSTRAINT `user_fk` FOREIGN KEY (`user_id`) REFERENCES `users` (`users_id`);

--
-- Constraints for table `shipping_details`
--
ALTER TABLE `shipping_details`
  ADD CONSTRAINT `shipper_provider_fk` FOREIGN KEY (`shipper_provider_id`) REFERENCES `shipping_providers` (`shipper_provider_id`);

--
-- Constraints for table `stock_events`
--
ALTER TABLE `stock_events`
  ADD CONSTRAINT `order_fk` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  ADD CONSTRAINT `product_fk3` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;

CREATE TABLE product (
    product_id INT PRIMARY KEY,
    product_name VARCHAR(100),
    supplier VARCHAR(100),
    product_cost DECIMAL(10, 2)
);

CREATE TABLE inventory (
    product_id INT,
    store_id INT,
    store_name VARCHAR(70),
    address VARCHAR(120),
    neighborhood VARCHAR(70),
    quantity_available INT,
    PRIMARY KEY (product_id, store_id),
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);

CREATE INDEX index_store_id ON inventory(store_id);
CREATE INDEX index_product_id ON inventory(product_id);
CREATE INDEX index_sale_product ON sale(product_id);
CREATE INDEX index_sale_store_id ON sale(store_id);
CREATE INDEX index_inv_product ON product(product_id);

CREATE TABLE sale (
    sale_id INT,
    store_id INT,
    product_id INT,
    date DATE,
    unit_price FLOAT,
    quantity INT,
    PRIMARY KEY (sale_id, product_id, store_id, date),
    FOREIGN KEY (product_id) REFERENCES product(product_id),
    FOREIGN KEY (store_id) REFERENCES inventory(store_id)
);

-- In order to allow data import
SET GLOBAL local_infile = 1;

-- Load data into the tables
LOAD DATA LOCAL INFILE 'D:/Documents/Data Analytics/Portfolio/SQL - Store Inventory/product.csv'
INTO TABLE product
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_id, product_name, supplier, product_cost);

LOAD DATA LOCAL INFILE 'D:/Documents/Data Analytics/Portfolio/SQL - Store Inventory/inventory.csv'
INTO TABLE inventory
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_id, store_id, store_name, address, neighborhood, quantity_available);

LOAD DATA LOCAL INFILE 'D:/Documents/Data Analytics/Portfolio/SQL - Store Inventory/sale.csv'
INTO TABLE sale
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(sale_id, store_id, product_id, date, unit_price, quantity);


-- Exploratory Data Analysis

-- Check for nulls in the product table
SELECT * 
FROM product
WHERE product_id IS NULL 
OR product_name IS NULL 
OR supplier IS NULL 
OR product_cost IS NULL; -- 0

-- Check for nulls in the inventory table
SELECT * 
FROM inventory
WHERE product_id IS NULL 
OR store_id IS NULL 
OR quantity_available IS NULL; -- 0

-- Check for nulls in the sale table
SELECT * 
FROM sale
WHERE sale_id IS NULL 
OR product_id IS NULL 
OR store_id IS NULL 
OR date IS NULL 
OR unit_price IS NULL 
OR quantity IS NULL; -- 0

-- Check for invalid product_ids in the inventory table
SELECT i.*
FROM inventory i
LEFT JOIN product p ON i.product_id = p.product_id
WHERE p.product_id IS NULL; -- 0

-- Check for invalid store_ids in the sale table
SELECT s.*
FROM sale s
LEFT JOIN inventory i ON s.store_id = i.store_id AND s.product_id = i.product_id
WHERE i.product_id IS NULL; -- There are some transactions that happened at a store even though
 -- the product was never listed in the inventory table 
 
-- Check for invalid product_ids in the sale table
SELECT s.*
FROM sale s
LEFT JOIN product p ON s.product_id = p.product_id
WHERE p.product_id IS NULL; -- 0

-- Check for negative or zero product cost in the product table
SELECT * 
FROM product
WHERE product_cost <= 0; -- 0

-- Check for negative or zero quantity in the inventory table
SELECT * 
FROM inventory
WHERE quantity_available < 0; -- 0

-- Check for negative or zero quantity in the sale table
SELECT * 
FROM sale
WHERE quantity <= 0; -- 0

-- Check for unusually high prices in the sale table (optional threshold example)
SELECT * 
FROM sale
WHERE unit_price > 1000; -- 0

-- Check for index efficiency
EXPLAIN SELECT * FROM sale WHERE product_id = 123 AND store_id = 456; -- very efficient

SELECT COUNT(DISTINCT product_id) AS available_products
FROM product; -- 1000 products available

SELECT COUNT(DISTINCT product_name) AS available_products
FROM product; -- 826 distinct names, meaning some IDs can be duplicate or if the product is organic can be named differently
	-- or the supplier is different
    
-- Select only the duplicate product names
SELECT p.product_id, p.product_name, p.supplier, p.product_cost
FROM product p
INNER JOIN (
    SELECT product_name
    FROM product
    GROUP BY product_name
    HAVING COUNT(*) > 1
) dup ON p.product_name = dup.product_name; -- large variation in prices between suppliers

SELECT COUNT(DISTINCT store_id) AS stores
FROM inventory; -- 34 stores

SELECT COUNT(DISTINCT store_id) AS stores
FROM sale; -- all stores have transactions

SELECT COUNT(DISTINCT product_id) AS available_products
FROM inventory; -- some products should be available to other stores?

SELECT i.product_id, p.product_name, i.store_id
FROM inventory i
JOIN product p ON i.product_id = p.product_id
WHERE p.product_name IN (
    SELECT product_name
    FROM product
    GROUP BY product_name
    HAVING COUNT(*) > 1
); -- products that have the same name and different id in the inventory table maybe because of logistics


-- Questions answered --
-- Which store has the most sales?
SELECT s.store_id, 
i.store_name,
ROUND(SUM(s.unit_price * s.quantity), 0) AS revenue
FROM sale AS s 
JOIN inventory AS i ON s.store_id = i.store_id
GROUP BY s.store_id, i.store_name
ORDER BY revenue DESC; -- Ben Franklin


-- What are the top-selling products by quantity, revenue, and store?
SELECT p.product_name, 
SUM(s.quantity) AS total_quantity
FROM sale AS s
JOIN product AS p ON s.product_id = p.product_id
GROUP BY p.product_name
ORDER BY total_quantity DESC; -- Rice paper and Banana Nut Muffins are the most sold items

SELECT p.product_name, 
ROUND(SUM(s.unit_price * s.quantity), 0) AS product_revenue
FROM sale AS s
JOIN product AS p ON s.product_id = p.product_id
GROUP BY p.product_name
ORDER BY product_revenue DESC; -- Sultanas and Green Chili Peppers are the highest revenue drivers
    
WITH ranked_products AS (
    SELECT 
        s.product_id, 
        p.product_name, 
        s.store_id,
        i.store_name,
        ROUND(SUM(s.unit_price * s.quantity),0) AS total_revenue,
        ROW_NUMBER() OVER (PARTITION BY s.store_id ORDER BY SUM(s.unit_price * s.quantity) DESC) AS top_performer
    FROM 
        sale AS s
    JOIN 
        product AS p ON s.product_id = p.product_id
	JOIN 
		inventory AS i ON s.store_id = i.store_id
    GROUP BY 
        s.product_id, p.product_name, s.store_id, i.store_name
)
SELECT 
    product_id, 
    product_name, 
    store_name, 
    total_revenue
FROM 
    ranked_products
WHERE 
    top_performer = 1
ORDER BY 
    total_revenue DESC; -- Rye flour at Ben Franlkin store is top-performer. 
    -- Also Sultanas and Pop Shoppe Cream Soda are popular at many stores.


-- Which products generate the most profit? What about the least profit?
SELECT p.product_id,
p.product_name, 
ROUND(AVG(s.unit_price-p.product_cost),2) AS profit
FROM sale AS s
JOIN product AS p ON s.product_id = p.product_id
GROUP BY p.product_id
ORDER BY profit DESC
LIMIT 7; -- Most profit is wanted, so limit is used. To get the least profitable eliminate "DESC" syntax.

-- Top 3 most profitable stores in 2019
SELECT i.store_name,
ROUND(SUM((s.unit_price-p.product_cost)*s.quantity),0) AS total_profit
FROM sale AS s
JOIN 
product AS p ON s.product_id = p.product_id
JOIN 
inventory AS i ON s.store_id = i.store_id
WHERE  YEAR(s.date) = 2019
GROUP BY i.store_name
ORDER BY total_profit DESC
LIMIT 3;

-- How does sales performance vary over time (monthly & annually)?
SELECT YEAR(s.date) AS year,
MONTH(s.date) AS month,
ROUND(SUM(s.unit_price * s.quantity),0) AS total_revenue
FROM
sale AS s
GROUP BY YEAR(s.date), MONTH(s.date)
ORDER BY year, month;

SELECT YEAR(s.date) AS year,
ROUND(SUM(s.unit_price * s.quantity),0) AS total_revenue
FROM
sale AS s
GROUP BY YEAR(s.date)
ORDER BY year; -- Best year: 2018


-- Which stores have excess inventory for certain products?
SELECT 
MAX(quantity_available) AS max_quantity
FROM inventory; -- Because the maximum quantity of a product is 12, it can be incurred that there
	-- is no excess of inventory.

-- Which is the largest transaction in terms of quantity?
SELECT 
YEAR(s.date) AS transaction_year,
s.sale_id,
SUM(s.quantity) AS total_quantity
FROM sale AS s
GROUP BY 
	YEAR(s.date), s.sale_id
ORDER BY
	total_quantity DESC
LIMIT 10; -- 411 products sold in one transaction, in 2019.

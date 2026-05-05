-- ============================================================
--   BUG TRACKING & PROJECT MANAGEMENT SYSTEM
--   Database  : MySQL
--   Level     : Advanced
--   Features  : Stored Procedures, Triggers, Views, Indexes
-- ============================================================

CREATE DATABASE IF NOT EXISTS bug_tracker;
USE bug_tracker;

-- ============================================================
-- 1. SCHEMA / TABLE DEFINITIONS
-- ============================================================

-- Departments
CREATE TABLE departments (
    dept_id     INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    description TEXT,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Users (Developers, Testers, Managers)
CREATE TABLE users (
    user_id     INT AUTO_INCREMENT PRIMARY KEY,
    dept_id     INT          NOT NULL,
    first_name  VARCHAR(50)  NOT NULL,
    last_name   VARCHAR(50)  NOT NULL,
    email       VARCHAR(100) NOT NULL UNIQUE,
    role        ENUM('admin','manager','developer','tester') NOT NULL,
    is_active   BOOLEAN      DEFAULT TRUE,
    created_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
);

-- Projects
CREATE TABLE projects (
    project_id    INT AUTO_INCREMENT PRIMARY KEY,
    name          VARCHAR(100)  NOT NULL,
    description   TEXT,
    manager_id    INT           NOT NULL,
    status        ENUM('planning','active','on_hold','completed','cancelled') DEFAULT 'planning',
    start_date    DATE,
    end_date      DATE,
    open_bug_count INT          DEFAULT 0,
    created_at    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (manager_id) REFERENCES users(user_id)
);

-- Sprints
CREATE TABLE sprints (
    sprint_id   INT AUTO_INCREMENT PRIMARY KEY,
    project_id  INT          NOT NULL,
    name        VARCHAR(100) NOT NULL,
    goal        TEXT,
    start_date  DATE         NOT NULL,
    end_date    DATE         NOT NULL,
    status      ENUM('planned','active','completed') DEFAULT 'planned',
    created_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

-- Bugs
CREATE TABLE bugs (
    bug_id       INT AUTO_INCREMENT PRIMARY KEY,
    project_id   INT          NOT NULL,
    sprint_id    INT,
    reported_by  INT          NOT NULL,
    title        VARCHAR(200) NOT NULL,
    description  TEXT,
    steps_to_reproduce TEXT,
    priority     ENUM('critical','high','medium','low') DEFAULT 'medium',
    severity     ENUM('blocker','major','minor','trivial') DEFAULT 'minor',
    status       ENUM('open','in_progress','resolved','closed','reopened') DEFAULT 'open',
    bug_type     ENUM('functional','ui','performance','security','regression') DEFAULT 'functional',
    environment  ENUM('development','staging','production') DEFAULT 'development',
    created_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    resolved_at  DATETIME,
    FOREIGN KEY (project_id)  REFERENCES projects(project_id),
    FOREIGN KEY (sprint_id)   REFERENCES sprints(sprint_id),
    FOREIGN KEY (reported_by) REFERENCES users(user_id)
);

-- Bug Assignments
CREATE TABLE bug_assignments (
    assignment_id INT AUTO_INCREMENT PRIMARY KEY,
    bug_id        INT       NOT NULL,
    assigned_to   INT       NOT NULL,
    assigned_by   INT       NOT NULL,
    assigned_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active     BOOLEAN   DEFAULT TRUE,
    FOREIGN KEY (bug_id)      REFERENCES bugs(bug_id),
    FOREIGN KEY (assigned_to) REFERENCES users(user_id),
    FOREIGN KEY (assigned_by) REFERENCES users(user_id)
);

-- Bug Comments
CREATE TABLE bug_comments (
    comment_id  INT AUTO_INCREMENT PRIMARY KEY,
    bug_id      INT       NOT NULL,
    user_id     INT       NOT NULL,
    comment     TEXT      NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (bug_id)  REFERENCES bugs(bug_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- Bug History (auto-filled by trigger)
CREATE TABLE bug_history (
    history_id  INT AUTO_INCREMENT PRIMARY KEY,
    bug_id      INT          NOT NULL,
    changed_by  INT,
    old_status  VARCHAR(50),
    new_status  VARCHAR(50),
    old_priority VARCHAR(50),
    new_priority VARCHAR(50),
    change_note TEXT,
    changed_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (bug_id) REFERENCES bugs(bug_id)
);

-- Notifications (auto-filled by trigger)
CREATE TABLE notifications (
    notification_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id         INT          NOT NULL,
    message         TEXT         NOT NULL,
    is_read         BOOLEAN      DEFAULT FALSE,
    created_at      TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- Attachments
CREATE TABLE attachments (
    attachment_id INT AUTO_INCREMENT PRIMARY KEY,
    bug_id        INT          NOT NULL,
    uploaded_by   INT          NOT NULL,
    file_name     VARCHAR(200) NOT NULL,
    file_type     VARCHAR(50),
    file_size_kb  INT,
    uploaded_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (bug_id)      REFERENCES bugs(bug_id),
    FOREIGN KEY (uploaded_by) REFERENCES users(user_id)
);

-- Test Cases
CREATE TABLE test_cases (
    test_id     INT AUTO_INCREMENT PRIMARY KEY,
    bug_id      INT          NOT NULL,
    created_by  INT          NOT NULL,
    title       VARCHAR(200) NOT NULL,
    steps       TEXT,
    expected    TEXT,
    actual      TEXT,
    result      ENUM('pass','fail','pending') DEFAULT 'pending',
    tested_at   DATETIME,
    FOREIGN KEY (bug_id)     REFERENCES bugs(bug_id),
    FOREIGN KEY (created_by) REFERENCES users(user_id)
);

-- Releases
CREATE TABLE releases (
    release_id   INT AUTO_INCREMENT PRIMARY KEY,
    project_id   INT          NOT NULL,
    version      VARCHAR(20)  NOT NULL,
    description  TEXT,
    release_date DATE,
    status       ENUM('upcoming','released','rolled_back') DEFAULT 'upcoming',
    created_at   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (project_id) REFERENCES projects(project_id)
);


-- ============================================================
-- 2. INDEXES (for performance)
-- ============================================================

CREATE INDEX idx_bugs_project    ON bugs(project_id);
CREATE INDEX idx_bugs_status     ON bugs(status);
CREATE INDEX idx_bugs_priority   ON bugs(priority);
CREATE INDEX idx_bugs_sprint     ON bugs(sprint_id);
CREATE INDEX idx_assignments_bug ON bug_assignments(bug_id);
CREATE INDEX idx_comments_bug    ON bug_comments(bug_id);
CREATE INDEX idx_history_bug     ON bug_history(bug_id);


-- ============================================================
-- 3. TRIGGERS
-- ============================================================

DELIMITER $$

-- Trigger 1: Auto-log bug history when status or priority changes
CREATE TRIGGER trg_bug_history
BEFORE UPDATE ON bugs
FOR EACH ROW
BEGIN
    IF OLD.status != NEW.status OR OLD.priority != NEW.priority THEN
        INSERT INTO bug_history (
            bug_id, old_status, new_status,
            old_priority, new_priority, change_note
        ) VALUES (
            OLD.bug_id,
            OLD.status,   NEW.status,
            OLD.priority, NEW.priority,
            CONCAT('Status changed from ', OLD.status, ' to ', NEW.status)
        );
    END IF;

    -- Auto-set resolved_at when bug is resolved
    IF NEW.status = 'resolved' AND OLD.status != 'resolved' THEN
        SET NEW.resolved_at = NOW();
    END IF;
END$$

-- Trigger 2: Auto-create notification when a bug is assigned
CREATE TRIGGER trg_assignment_notification
AFTER INSERT ON bug_assignments
FOR EACH ROW
BEGIN
    INSERT INTO notifications (user_id, message)
    VALUES (
        NEW.assigned_to,
        CONCAT('You have been assigned a new bug ID: ', NEW.bug_id,
               '. Please check and start working on it.')
    );
END$$

-- Trigger 3: Auto-increment open_bug_count when new bug is opened
CREATE TRIGGER trg_bug_count_insert
AFTER INSERT ON bugs
FOR EACH ROW
BEGIN
    IF NEW.status = 'open' THEN
        UPDATE projects
        SET open_bug_count = open_bug_count + 1
        WHERE project_id = NEW.project_id;
    END IF;
END$$

-- Trigger 4: Auto-decrement open_bug_count when bug is resolved/closed
CREATE TRIGGER trg_bug_count_update
AFTER UPDATE ON bugs
FOR EACH ROW
BEGIN
    IF OLD.status = 'open' AND NEW.status IN ('resolved','closed') THEN
        UPDATE projects
        SET open_bug_count = open_bug_count - 1
        WHERE project_id = NEW.project_id;
    END IF;
    IF NEW.status = 'open' AND OLD.status IN ('resolved','closed') THEN
        UPDATE projects
        SET open_bug_count = open_bug_count + 1
        WHERE project_id = NEW.project_id;
    END IF;
END$$

DELIMITER ;


-- ============================================================
-- 4. STORED PROCEDURES
-- ============================================================

DELIMITER $$

-- SP 1: Create a new bug
CREATE PROCEDURE sp_create_bug (
    IN p_project_id   INT,
    IN p_sprint_id    INT,
    IN p_reported_by  INT,
    IN p_title        VARCHAR(200),
    IN p_description  TEXT,
    IN p_priority     VARCHAR(20),
    IN p_severity     VARCHAR(20),
    IN p_bug_type     VARCHAR(20),
    IN p_environment  VARCHAR(20)
)
BEGIN
    INSERT INTO bugs (
        project_id, sprint_id, reported_by, title,
        description, priority, severity, bug_type, environment
    ) VALUES (
        p_project_id, p_sprint_id, p_reported_by, p_title,
        p_description, p_priority, p_severity, p_bug_type, p_environment
    );
    SELECT LAST_INSERT_ID() AS new_bug_id,
           'Bug created successfully' AS message;
END$$

-- SP 2: Assign a bug to a developer
CREATE PROCEDURE sp_assign_bug (
    IN p_bug_id      INT,
    IN p_assigned_to INT,
    IN p_assigned_by INT
)
BEGIN
    -- Deactivate previous assignment
    UPDATE bug_assignments
    SET is_active = FALSE
    WHERE bug_id = p_bug_id AND is_active = TRUE;

    -- Create new assignment
    INSERT INTO bug_assignments (bug_id, assigned_to, assigned_by)
    VALUES (p_bug_id, p_assigned_to, p_assigned_by);

    -- Update bug status to in_progress
    UPDATE bugs SET status = 'in_progress'
    WHERE bug_id = p_bug_id;

    SELECT 'Bug assigned successfully' AS message;
END$$

-- SP 3: Resolve a bug
CREATE PROCEDURE sp_resolve_bug (
    IN p_bug_id   INT,
    IN p_user_id  INT,
    IN p_comment  TEXT
)
BEGIN
    UPDATE bugs SET status = 'resolved'
    WHERE bug_id = p_bug_id;

    INSERT INTO bug_comments (bug_id, user_id, comment)
    VALUES (p_bug_id, p_user_id, CONCAT('[RESOLVED] ', p_comment));

    SELECT 'Bug resolved successfully' AS message;
END$$

-- SP 4: Sprint Summary Report
CREATE PROCEDURE sp_sprint_report (
    IN p_sprint_id INT
)
BEGIN
    SELECT
        s.name                              AS sprint_name,
        s.start_date,
        s.end_date,
        s.status                            AS sprint_status,
        COUNT(b.bug_id)                     AS total_bugs,
        SUM(b.status = 'open')              AS open_bugs,
        SUM(b.status = 'in_progress')       AS in_progress_bugs,
        SUM(b.status = 'resolved')          AS resolved_bugs,
        SUM(b.status = 'closed')            AS closed_bugs,
        SUM(b.priority = 'critical')        AS critical_bugs,
        ROUND(
            SUM(b.status IN ('resolved','closed')) * 100.0 / COUNT(b.bug_id), 2
        )                                   AS completion_percentage
    FROM sprints s
    LEFT JOIN bugs b ON s.sprint_id = b.sprint_id
    WHERE s.sprint_id = p_sprint_id
    GROUP BY s.sprint_id;
END$$

-- SP 5: Project Health Report
CREATE PROCEDURE sp_project_report (
    IN p_project_id INT
)
BEGIN
    SELECT
        p.name                              AS project_name,
        p.status                            AS project_status,
        p.start_date,
        p.end_date,
        CONCAT(u.first_name,' ',u.last_name) AS manager,
        COUNT(b.bug_id)                     AS total_bugs,
        SUM(b.status = 'open')              AS open_bugs,
        SUM(b.status = 'resolved')          AS resolved_bugs,
        SUM(b.priority = 'critical')        AS critical_bugs,
        SUM(b.priority = 'high')            AS high_priority_bugs,
        p.open_bug_count                    AS current_open_count
    FROM projects p
    JOIN users u ON p.manager_id = u.user_id
    LEFT JOIN bugs b ON p.project_id = b.project_id
    WHERE p.project_id = p_project_id
    GROUP BY p.project_id;
END$$

DELIMITER ;


-- ============================================================
-- 5. VIEWS
-- ============================================================

-- View 1: Open bugs with assigned developer
CREATE VIEW vw_open_bugs AS
SELECT
    b.bug_id,
    p.name                               AS project,
    b.title,
    b.priority,
    b.severity,
    b.bug_type,
    b.environment,
    CONCAT(u1.first_name,' ',u1.last_name) AS reported_by,
    CONCAT(u2.first_name,' ',u2.last_name) AS assigned_to,
    b.created_at
FROM bugs b
JOIN projects p   ON b.project_id   = p.project_id
JOIN users u1     ON b.reported_by  = u1.user_id
LEFT JOIN bug_assignments ba ON b.bug_id = ba.bug_id AND ba.is_active = TRUE
LEFT JOIN users u2 ON ba.assigned_to = u2.user_id
WHERE b.status IN ('open','in_progress','reopened');

-- View 2: Developer performance
CREATE VIEW vw_developer_performance AS
SELECT
    CONCAT(u.first_name,' ',u.last_name)  AS developer,
    u.email,
    COUNT(ba.bug_id)                       AS total_assigned,
    SUM(b.status IN ('resolved','closed')) AS total_resolved,
    SUM(b.status = 'open')                 AS currently_open,
    ROUND(
        AVG(TIMESTAMPDIFF(HOUR, b.created_at, b.resolved_at)), 2
    )                                      AS avg_resolution_hours
FROM users u
JOIN bug_assignments ba ON u.user_id = ba.assigned_to
JOIN bugs b             ON ba.bug_id = b.bug_id
WHERE u.role = 'developer'
GROUP BY u.user_id;


-- ============================================================
-- 6. SAMPLE DATA
-- ============================================================

-- Departments
INSERT INTO departments (name, description) VALUES
('Engineering',      'Core software development team'),
('Quality Assurance','Testing and quality control team'),
('DevOps',           'Infrastructure and deployment team'),
('Product',          'Product management and design team');

-- Users
INSERT INTO users (dept_id, first_name, last_name, email, role) VALUES
(4, 'Arjun',    'Sharma',   'arjun.sharma@techco.com',   'admin'),
(4, 'Priya',    'Nair',     'priya.nair@techco.com',     'manager'),
(4, 'Rahul',    'Verma',    'rahul.verma@techco.com',    'manager'),
(1, 'Sneha',    'Iyer',     'sneha.iyer@techco.com',     'developer'),
(1, 'Vikram',   'Singh',    'vikram.singh@techco.com',   'developer'),
(1, 'Karthik',  'Raj',      'karthik.raj@techco.com',    'developer'),
(1, 'Ananya',   'Das',      'ananya.das@techco.com',     'developer'),
(2, 'Meera',    'Pillai',   'meera.pillai@techco.com',   'tester'),
(2, 'Siddharth','Bose',     'siddharth.bose@techco.com', 'tester'),
(2, 'Divya',    'Menon',    'divya.menon@techco.com',    'tester'),
(3, 'Naveen',   'Reddy',    'naveen.reddy@techco.com',   'developer'),
(1, 'Geeta',    'Agarwal',  'geeta.agarwal@techco.com',  'developer');

-- Projects
INSERT INTO projects (name, description, manager_id, status, start_date, end_date) VALUES
('EduPortal',      'Online education management platform',      2, 'active',    '2025-01-01', '2025-06-30'),
('PaySwift',       'Digital payments and wallet application',   3, 'active',    '2025-02-01', '2025-08-31'),
('HealthTrack',    'Patient health monitoring system',          2, 'planning',  '2025-04-01', '2025-12-31'),
('LogiTrack',      'Logistics and shipment tracking platform',  3, 'completed', '2024-06-01', '2024-12-31');

-- Sprints
INSERT INTO sprints (project_id, name, goal, start_date, end_date, status) VALUES
(1, 'Sprint 1', 'User authentication and dashboard',    '2025-01-10', '2025-01-24', 'completed'),
(1, 'Sprint 2', 'Course management module',             '2025-01-25', '2025-02-08', 'completed'),
(1, 'Sprint 3', 'Payment integration',                  '2025-02-09', '2025-02-23', 'active'),
(2, 'Sprint 1', 'Wallet setup and KYC',                 '2025-02-10', '2025-02-24', 'completed'),
(2, 'Sprint 2', 'Transaction history and reports',      '2025-02-25', '2025-03-11', 'active'),
(4, 'Sprint 1', 'Shipment tracking core module',        '2024-06-10', '2024-06-24', 'completed');

-- Bugs
INSERT INTO bugs (project_id, sprint_id, reported_by, title, description, priority, severity, status, bug_type, environment) VALUES
(1,1,8,  'Login page crashes on wrong password',   'App crashes instead of showing error message',          'critical','blocker',  'resolved',    'functional',  'production'),
(1,1,9,  'Dashboard not loading for new users',    'Blank screen shown after first login',                  'high',    'major',    'resolved',    'functional',  'staging'),
(1,2,8,  'Course thumbnail not displaying',        'Images broken on course listing page',                  'medium',  'minor',    'resolved',    'ui',          'development'),
(1,3,10, 'Payment gateway timeout after 30 sec',   'Payment fails silently after timeout with no feedback', 'critical','blocker',  'open',        'functional',  'staging'),
(1,3,9,  'Discount coupon not applying correctly', 'Coupon deduction shows wrong amount',                   'high',    'major',    'in_progress', 'functional',  'staging'),
(2,4,10, 'KYC document upload fails on mobile',    'File picker crashes on Android devices',                'critical','blocker',  'resolved',    'functional',  'production'),
(2,4,8,  'OTP not received on some networks',      'OTP delivery fails for certain telecom providers',      'high',    'major',    'in_progress', 'functional',  'production'),
(2,5,9,  'Transaction history shows duplicate entries','Same transaction appears twice in history',         'high',    'major',    'open',        'functional',  'staging'),
(2,5,10, 'Export to PDF button not working',       'Nothing happens when PDF export is clicked',            'medium',  'minor',    'open',        'functional',  'development'),
(1,2,8,  'Search filter not working on courses',   'Filtering by category returns all courses',             'medium',  'minor',    'closed',      'functional',  'development'),
(2,4,9,  'UI misaligned on iPad screen size',      'Buttons overlap on tablet viewport',                    'low',     'trivial',  'open',        'ui',          'staging'),
(1,1,10, 'Password reset email not sent',          'Reset link not delivered to inbox or spam',             'high',    'major',    'resolved',    'functional',  'production');

-- Bug Assignments
INSERT INTO bug_assignments (bug_id, assigned_to, assigned_by, is_active) VALUES
(1,  4, 2, FALSE),
(2,  5, 2, FALSE),
(3,  7, 2, FALSE),
(4,  4, 2, TRUE),
(5,  6, 2, TRUE),
(6,  5, 3, FALSE),
(7,  6, 3, TRUE),
(8,  4, 3, TRUE),
(9,  7, 3, TRUE),
(10, 5, 2, FALSE),
(11, 7, 3, TRUE),
(12, 4, 2, FALSE);

-- Bug Comments
INSERT INTO bug_comments (bug_id, user_id, comment) VALUES
(1,  4,  'Reproduced the issue. Root cause is null pointer exception in auth handler.'),
(1,  4,  '[RESOLVED] Fixed null check in AuthController.java. Deployed to production.'),
(2,  5,  'Issue is in dashboard loader — API call fails silently on first login.'),
(2,  5,  '[RESOLVED] Added retry logic and error handling for initial API call.'),
(4,  4,  'Investigating — looks like gateway response timeout is not handled.'),
(5,  6,  'Coupon validation logic has a rounding error. Working on fix.'),
(7,  6,  'Checked with telecom APIs — issue with DLT registration. Escalating.'),
(12, 4,  '[RESOLVED] SMTP config was missing for production environment. Fixed.');

-- Attachments
INSERT INTO attachments (bug_id, uploaded_by, file_name, file_type, file_size_kb) VALUES
(1,  8,  'login_crash_screenshot.png', 'image/png',       245),
(4,  10, 'payment_timeout_log.txt',    'text/plain',       18),
(5,  9,  'coupon_bug_screenrecord.mp4','video/mp4',      3200),
(7,  10, 'otp_failure_log.txt',        'text/plain',       12),
(11, 9,  'ipad_ui_screenshot.png',     'image/png',       310);

-- Test Cases
INSERT INTO test_cases (bug_id, created_by, title, steps, expected, actual, result, tested_at) VALUES
(1, 8, 'Login with wrong password',
    '1. Go to login page\n2. Enter wrong password\n3. Click login',
    'Show error: Invalid credentials',
    'App crashes with 500 error',
    'pass', '2025-01-15 10:30:00'),
(2, 9, 'Dashboard load for new user',
    '1. Register new user\n2. Login\n3. Check dashboard',
    'Dashboard loads with welcome screen',
    'Blank white screen displayed',
    'pass', '2025-01-18 14:00:00'),
(4, 10, 'Payment gateway timeout handling',
    '1. Initiate payment\n2. Wait 30 seconds',
    'Show timeout error message to user',
    'Silent failure with no feedback',
    'fail', '2025-03-01 09:00:00'),
(5, 8, 'Apply discount coupon',
    '1. Add item to cart\n2. Apply coupon CODE10\n3. Check total',
    'Discount applied correctly',
    'Wrong deduction shown',
    'fail', '2025-03-05 11:00:00');

-- Releases
INSERT INTO releases (project_id, version, description, release_date, status) VALUES
(1, 'v1.0.0', 'Initial launch with auth and dashboard',       '2025-01-28', 'released'),
(1, 'v1.1.0', 'Course management and search features',        '2025-02-15', 'released'),
(1, 'v1.2.0', 'Payment integration and coupon system',        '2025-03-15', 'upcoming'),
(2, 'v1.0.0', 'Wallet setup, KYC and basic transactions',     '2025-03-01', 'released'),
(4, 'v2.0.0', 'Full logistics tracking with real-time maps',  '2024-12-15', 'released');


-- ============================================================
-- 7. USEFUL QUERIES
-- ============================================================

-- Q1: All open and in-progress bugs with priority
SELECT * FROM vw_open_bugs ORDER BY
    FIELD(priority,'critical','high','medium','low');

-- Q2: Developer performance report
SELECT * FROM vw_developer_performance
ORDER BY total_resolved DESC;

-- Q3: Bug count by priority per project
SELECT
    p.name          AS project,
    b.priority,
    COUNT(*)        AS total_bugs
FROM bugs b
JOIN projects p ON b.project_id = p.project_id
GROUP BY p.project_id, b.priority
ORDER BY p.name, FIELD(b.priority,'critical','high','medium','low');

-- Q4: Average bug resolution time per developer (in hours)
SELECT
    CONCAT(u.first_name,' ',u.last_name)        AS developer,
    COUNT(b.bug_id)                              AS bugs_resolved,
    ROUND(AVG(TIMESTAMPDIFF(HOUR,
        b.created_at, b.resolved_at)),2)         AS avg_hours_to_resolve
FROM users u
JOIN bug_assignments ba ON u.user_id   = ba.assigned_to
JOIN bugs b             ON ba.bug_id   = b.bug_id
WHERE b.status IN ('resolved','closed')
  AND b.resolved_at IS NOT NULL
GROUP BY u.user_id
ORDER BY avg_hours_to_resolve;

-- Q5: Most critical open bugs across all projects
SELECT
    b.bug_id,
    p.name      AS project,
    b.title,
    b.priority,
    b.severity,
    b.environment,
    CONCAT(u.first_name,' ',u.last_name) AS reported_by,
    b.created_at
FROM bugs b
JOIN projects p ON b.project_id  = p.project_id
JOIN users    u ON b.reported_by = u.user_id
WHERE b.status IN ('open','in_progress')
  AND b.priority IN ('critical','high')
ORDER BY FIELD(b.priority,'critical','high'), b.created_at;

-- Q6: Bug history / audit trail for a specific bug
SELECT
    bh.bug_id,
    bh.old_status,
    bh.new_status,
    bh.old_priority,
    bh.new_priority,
    bh.change_note,
    bh.changed_at
FROM bug_history bh
WHERE bh.bug_id = 1
ORDER BY bh.changed_at;

-- Q7: Notifications for a specific user
SELECT message, is_read, created_at
FROM notifications
WHERE user_id = 4
ORDER BY created_at DESC;

-- Q8: Sprint completion rate
SELECT
    s.name          AS sprint,
    p.name          AS project,
    COUNT(b.bug_id) AS total_bugs,
    SUM(b.status IN ('resolved','closed')) AS done,
    ROUND(SUM(b.status IN ('resolved','closed')) * 100.0 / COUNT(b.bug_id), 2)
                    AS completion_pct
FROM sprints s
JOIN projects p ON s.project_id = p.project_id
LEFT JOIN bugs b ON s.sprint_id = b.sprint_id
GROUP BY s.sprint_id
ORDER BY completion_pct DESC;

-- Q9: Bugs reported per tester
SELECT
    CONCAT(u.first_name,' ',u.last_name) AS tester,
    COUNT(b.bug_id)                       AS bugs_reported,
    SUM(b.priority = 'critical')          AS critical,
    SUM(b.priority = 'high')              AS high,
    SUM(b.priority = 'medium')            AS medium,
    SUM(b.priority = 'low')               AS low
FROM users u
JOIN bugs b ON u.user_id = b.reported_by
WHERE u.role = 'tester'
GROUP BY u.user_id
ORDER BY bugs_reported DESC;

-- Q10: Project open bug count summary
SELECT
    name            AS project,
    status,
    open_bug_count,
    start_date,
    end_date
FROM projects
ORDER BY open_bug_count DESC;

-- ============================================================
-- 8. HOW TO USE STORED PROCEDURES
-- ============================================================

-- Create a new bug:
-- CALL sp_create_bug(1, 3, 8, 'New UI bug on checkout', 'Button missing', 'high', 'major', 'ui', 'staging');

-- Assign bug to developer:
-- CALL sp_assign_bug(4, 6, 2);

-- Resolve a bug:
-- CALL sp_resolve_bug(5, 6, 'Fixed rounding error in coupon calculation logic.');

-- Sprint report:
-- CALL sp_sprint_report(3);

-- Project health report:
-- CALL sp_project_report(1);

-- ============================================================
-- END OF PROJECT
-- ============================================================

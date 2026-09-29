CREATE TABLE IF NOT EXISTS `placed_peds` (
    `id`            INT(11)       NOT NULL AUTO_INCREMENT,
    `model`         VARCHAR(100)  NOT NULL,
    `x`             FLOAT         NOT NULL,
    `y`             FLOAT         NOT NULL,
    `z`             FLOAT         NOT NULL,
    `heading`       FLOAT         NOT NULL DEFAULT 0.0,
    `scenario`      VARCHAR(100)  NOT NULL DEFAULT '',
    `weapon`        VARCHAR(100)  NOT NULL DEFAULT '',
    `invincible`    TINYINT(1)    NOT NULL DEFAULT 1,
    `frozen`        TINYINT(1)    NOT NULL DEFAULT 1,
    `label`         VARCHAR(100)  NOT NULL DEFAULT 'Custom Ped',
    `placed_by`     VARCHAR(100)  NOT NULL DEFAULT 'unknown',
    `behavior`      VARCHAR(50)   NOT NULL DEFAULT 'idle',
    `wander_radius` FLOAT         NOT NULL DEFAULT 15.0,
    `patrol_speed`  FLOAT         NOT NULL DEFAULT 1.0,
    `patrol_points` TEXT          NULL DEFAULT NULL,
    `interact_type` VARCHAR(100)  NOT NULL DEFAULT '',
    `group_name`    VARCHAR(100)  NOT NULL DEFAULT '',
    `anim_dict`     VARCHAR(200)  NOT NULL DEFAULT '',
    `anim_name`     VARCHAR(200)  NOT NULL DEFAULT '',
    `emote_props`   LONGTEXT      NULL DEFAULT NULL,
    `created_at`    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_group` (`group_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `ped_groups` (
    `id`            INT(11)       NOT NULL AUTO_INCREMENT,
    `name`          VARCHAR(100)  NOT NULL,
    `description`   VARCHAR(255)  NOT NULL DEFAULT '',
    `data`          LONGTEXT      NOT NULL,
    `created_by`    VARCHAR(100)  NOT NULL DEFAULT 'unknown',
    `created_at`    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `idx_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

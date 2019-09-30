# mysql 主从

## mysq如何实现的呢？
>会使用binlog特点=>记录执行的sql语句，复制功能
>mysql5使用复制模块->执行的异步
>docker 获取root权限 docker exec --user root -it mysql-1 bash

## 主从注意点、原则
1.不能有太多的备库
2.一个备库实例 只能有一个主库
3.每个集群库 主库和从库都必须要唯一的服务ID ==>server_id
4.一个主库是可以有多个备库

## master-slave实现过程
1.开启主库的binlog  my.cnf
    -- server_id=1
    -- bin-log=mysql-bin
2.主库中配置复制账号
    -- repl_131:repl_131
    
3.分配账号权限：复制权限 replication slave
4.配置从库配置文件 添加中继
5.启动复制
start slave

# 1 主从 搭建 

    使用 mysql-1主 mysql-2从 手动搭建

## 0.机器准备：

    192.168.5.11   192.168.5.12 端口都是3306
    
##  1.创建账号

```sh
#创建账号sql
create user 'username'@'localhost' identified by 'password';

#授权
grant [权限] on *.* to 'username'@'localhost' identified by 'password';

mysql> create user 'repl_12'@'%' identified by 'repl_12';
Query OK, 0 rows affected (0.02 sec)

mysql> select user,host from mysql.user;
+---------------+-----------+
| user          | host      |
+---------------+-----------+
| repl_12       | %         |
| root          | %         |
| mysql.session | localhost |
| mysql.sys     | localhost |
| root          | localhost |
+---------------+-----------+
5 rows in set (0.00 sec)

mysql> grant replication slave on *.* to 'repl_12'@'%' identified by 'repl_12';
Query OK, 0 rows affected, 1 warning (0.00 sec)

mysql> show global variables like '%log_bin%';
+---------------------------------+-------+
| Variable_name                   | Value |
+---------------------------------+-------+
| log_bin                         | OFF   |
| log_bin_basename                |       |
| log_bin_index                   |       |
| log_bin_trust_function_creators | OFF   |
| log_bin_use_v1_row_events       | OFF   |
+---------------------------------+-------+
5 rows in set (0.01 sec)

#log_bin 是 off 状态，需要打开
# log-bin[=file_name]
[root@localhost panel]# vi /etc/mysql/my.cnf
#添加配置
[mysqld]
log-bin = mysql-bin
server-id = 11   #这个需要唯一在一个主从中

#保存退出，重启mysql

mysql> show global variables like '%log_bin%';
+---------------------------------+-------------------------------------+
| Variable_name                   | Value                               |
+---------------------------------+-------------------------------------+
| log_bin                         | ON                                  |
| log_bin_basename                | /var/lib/mysql/data/mysql-bin       |
| log_bin_index                   | /var/lib/mysql/data/mysql-bin.index |
| log_bin_trust_function_creators | OFF                                 |
| log_bin_use_v1_row_events       | OFF                                 |
+---------------------------------+-------------------------------------+
5 rows in set (0.01 sec)

```

## 2.binlog数据恢复操作

>查看MySQL的日志文件，这是查询主服务器上当前的二进制日志名和偏移值。
>这个槽的目的是为了在从数据库启动以后，从这个点进行数据库的恢复

```sh
mysql> show master status;
+------------------+----------+--------------+------------------+-------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set |
+------------------+----------+--------------+------------------+-------------------+
| mysql-bin.000002 |      154 |              |                  |                   |
+------------------+----------+--------------+------------------+-------------------+
1 row in set (0.00 sec)

```

对于binlog来说mysql-bin.xxx就是binlog的节点日志文件，而mysql-bin.index这是日志文件的所有会记录的。是所有日志文件的地址

```sh
bash-4.2$ more mysql-bin.index 
./mysql-bin.000001
./mysql-bin.000002

```

我们可以看看binlog日志中的信息
```sh
-- 查看二进制日志信息


# mysqlbinlog filename
bash-4.2$ mysqlbinlog ./mysql-bin.000002



# show binlog events in 'filename'\G;
mysql> show binlog events in 'mysql-bin.000002'\G


```

-- 查看所有二进制文件信息
show binary logs;
-- 查看最新二进制文件
show master status;
-- 刷新日志
flush logs; 新加一个版本
-- 清空所有的日志文件
reset master 还原成第一个版本

构建数据

```sh
mysql> select * from t;
+------+-----------+
| id   | name      |
+------+-----------+
|    1 | sixstar   |
|    2 | shineyork |
|    3 | xxx       |
+------+-----------+
3 rows in set (0.00 sec)

```

二进制文件信息

```sh
mysql> show binlog events in 'mysql-bin.000001';
+------------------+------+----------------+-----------+-------------+-----------------------------------------------------------------------+
| Log_name         | Pos  | Event_type     | Server_id | End_log_pos | Info                                                                  |
+------------------+------+----------------+-----------+-------------+-----------------------------------------------------------------------+
| mysql-bin.000001 |    4 | Format_desc    |        11 |         123 | Server ver: 5.7.24-log, Binlog ver: 4                                 |
| mysql-bin.000001 |  123 | Previous_gtids |        11 |         154 |                                                                       |
| mysql-bin.000001 |  154 | Anonymous_Gtid |        11 |         219 | SET @@SESSION.GTID_NEXT= 'ANONYMOUS'                                  |
| mysql-bin.000001 |  219 | Query          |        11 |         337 | CREATE DATABASE bin DEFAULT CHARACTER SET utf8                        |
| mysql-bin.000001 |  337 | Anonymous_Gtid |        11 |         402 | SET @@SESSION.GTID_NEXT= 'ANONYMOUS'                                  |
| mysql-bin.000001 |  402 | Query          |        11 |         532 | use `bin`; CREATE TABLE `t` (
  `id` int(10) ,
  `name` varchar(20)
) |
| mysql-bin.000001 |  532 | Anonymous_Gtid |        11 |         597 | SET @@SESSION.GTID_NEXT= 'ANONYMOUS'                                  |
| mysql-bin.000001 |  597 | Query          |        11 |         668 | BEGIN                                                                 |
| mysql-bin.000001 |  668 | Table_map      |        11 |         714 | table_id: 108 (bin.t)                                                 |
| mysql-bin.000001 |  714 | Write_rows     |        11 |         762 | table_id: 108 flags: STMT_END_F                                       |
| mysql-bin.000001 |  762 | Xid            |        11 |         793 | COMMIT /* xid=23 */                                                   |
| mysql-bin.000001 |  793 | Anonymous_Gtid |        11 |         858 | SET @@SESSION.GTID_NEXT= 'ANONYMOUS'                                  |
| mysql-bin.000001 |  858 | Query          |        11 |         929 | BEGIN                                                                 |
| mysql-bin.000001 |  929 | Table_map      |        11 |         975 | table_id: 108 (bin.t)                                                 |
| mysql-bin.000001 |  975 | Write_rows     |        11 |        1025 | table_id: 108 flags: STMT_END_F                                       |
| mysql-bin.000001 | 1025 | Xid            |        11 |        1056 | COMMIT /* xid=24 */                                                   |
| mysql-bin.000001 | 1056 | Anonymous_Gtid |        11 |        1121 | SET @@SESSION.GTID_NEXT= 'ANONYMOUS'                                  |
| mysql-bin.000001 | 1121 | Query          |        11 |        1192 | BEGIN                                                                 |
| mysql-bin.000001 | 1192 | Table_map      |        11 |        1238 | table_id: 108 (bin.t)                                                 |
| mysql-bin.000001 | 1238 | Write_rows     |        11 |        1282 | table_id: 108 flags: STMT_END_F                                       |
| mysql-bin.000001 | 1282 | Xid            |        11 |        1313 | COMMIT /* xid=25 */                                                   |
+------------------+------+----------------+-----------+-------------+-----------------------------------------------------------------------+
21 rows in set (0.00 sec)
```

接下来做个操作就是对表t中的数据进行删除所有的数据（这是模拟某些不小心的同学做的操作）

```sh
mysql> delete from t where id>1;
Query OK, 2 rows affected (0.01 sec)

mysql> select * from t;
+------+---------+
| id   | name    |
+------+---------+
|    1 | sixstar |
+------+---------+
1 row in set (0.00 sec)
```

现在来做恢复；根据数据情况找到数据的节点位置，发现是1079开始到1548结束

```sh
root@fb31fc16d255:/var/lib/mysql# mysqlbinlog mysql-bin.000001 --start-position 1079 --stop-position 1548  | mysql -u root -p
Enter password: 
```

## 3.配置从节点

要先明确配置的架构Master-slave

1. 配置主节点
   1.1 配置账号
   1.2 开启binlog日志
2. 配置从节点
   2.1 配置同步日志
   2.2 指定主节点的ip， 端口， 用户..
   2.3 启动从节点

### 3.1 配置同步日志

修改配置

修改配置

```sh
[root@localhost ~]# find / -name my.cnf
/etc/my.cnf
[root@localhost ~]# vi /etc/my.cnf
[root@localhost ~]# find / -name mysqld
/etc/rc.d/init.d/mysqld
/www/server/mysql/bin/mysqld
[root@localhost ~]# /etc/rc.d/init.d/mysqld restart
Shutting down MySQL.. SUCCESS!
Starting MySQL. SUCCESS!
```

在配置文件中添加

```sh
# 配置从节点
server-id = 2
relay_log = /www/server/data/mysql-relay-bin
relay_log-index = /www/server/data/mysql-relay-bin.index

log_slave_updates = 1
read_only = 1
```

### 3.2指定主节点的IP 端口  用户

```sh
mysql> change master to master_host='192.168.5.11',master_port=3306,master_user='repl_12',master_password='repl_12',master_log_file='mysql-bin.000001',master_log_pos=0;
Query OK, 0 rows affected, 2 warnings (0.03 sec)

```

### 3.3 启动从节点

```sh
mysql> start slave;
Query OK, 0 rows affected (0.01 sec)

mysql> show slave status\G;

#主要关系参数
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
```

reset slave all 清除salve信息

测试的方法就是在主服务器中，添加一些数据测试观察从服务中数据是否变化


搞定！






# 主从 搭建 使用 mysql-3主 mysql-4从 （自动搭建）

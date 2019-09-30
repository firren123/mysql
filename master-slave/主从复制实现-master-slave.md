# 主从复制实现

## 1. MYSQL主要复制启动配置

| 参数  | 作用 | 实例 |
|---|
|replicate-do-table     |指定需要复制的表   |replicate-do-table=test.rep_t1|
|replicate-ignore-table |指定不复制的表     |replicate-ignore-table=test.rep_t1|
|replicate-do-db        |指定复制的数据库   |replicate-db=db1|
|replicate-ignore-db    |指定不复制的数据库  |replicate-ignore-db=db2|

MySOL安装配置的时候，已经介绍了几个启动时的常用参数，其中包括MASTER HOST、MASTER PORT、MASTER_USER、MASTER PASSWORD、MASTER_LOG_FILE 和MASTER LOG POS。这几个参数需要在从服务器上配置，下面介绍几个常用的启动选项，如log-slave-updates、master-connect-retry、read-only 和slave-skip-errors等。

（1）log-slave-updates log-slave updates 参数主要用来配置从服务器的更新是否写入二进制日志，该选项默认是不打开的，如果这个从服务器同时也作为其他服务器的主服务器，搭建一个链式的复制，那么就需要开启这个选项，这样他的从服务器才能获取它的二进制日志进行同步操作。

（2）master-connect-retry master-connect-retry参数是用来设置在和主服务器连接丢失的时候，重试的时间间隔，默认是60秒。

（3）read-only read-only是用来限制普通用户对从数据库的更新操作，以确保从数据库的安全性，不过如果是超级用户依然可以对从数据库进行更新操作。如果主数据库创建了一个普通用户，在默认情况下，该用户是可以更新从数据库中的数据的，如果使用read-only选项启动从数据库以后，该用户对从数据库的更新会提示错误。使用read-only选项启动语法如下。

（4）slave-skip-errors 在复制的过程中，从服务器可能会执行BINLOG中的错误的SQL语句，此时如果不忽略错误，从服务器将会停止复制进程，等待用户处理错误。这种错误如果不能及时发现，将会对应用或者备份产生影响。slave-skip-errors的作用就是用来定义复制过程中从服务器可以自动跳过的错误号，设置该参数后，MySQL会自动跳过所配置的一系列错误，直接执行后面的SQL语句，该参数可以定义多个错误号，如果设置成all，则表示跳过所有的错误，具体语法如下。

```sh
vi /etc/my. cnf
slave-skip-errors=1007,1051,1062

```

如果从数据库主要是作为主数据库的备份，那么就不应该使用这个启动参数，设置不当，很可能造成主从数据库的数据不同步。如果从数据库仅仅是为了分担主数据库的查询压力，并且对数据的完整性要求不是很严格，那么这个选项可以减轻数据库管理源维护从数据库的工作量。

## 2.实际情况

在实际的工作中，我们一般对于数据库优化或者进行架构的时候主数据库往往是会有数据的，而从一开始就进行主从的基本很少。 所以这并非我们实际的情况。

现在我们的情况就是在数据库中已经事先就存在了laravel-shop的数据表，并且我们可以往里面添加一些数据作为测试用的，而根据主从来说同步的是binlog日志中的信息，但是一般数据库开始的时候并不会直接开启binlog，默认就是off需要修改配置调整为on

有几种办法来初始化备库或者从其他服务器克隆数据大备库。包括从主库复制数据、从另一台备库克隆数据等等主要的思路就是

1.在某个时间点的主库的数据快照。
2.主库当前的二进制日志文件，和获得数据快照是，在该二进制日志文件中的偏移量，我们把这两个值成为日志文件坐标。通过这两个值可以确定二进制日志的位置。可以通过SHOW MASTER STATUS命令来获取这些值。
3.从快照时间到现在的二进制日志。

### 2.1冷备份与恢复

#### 2.1.1 逻辑备份

> 1. 我们可以通过在从服务上创建laravel-shop的数据库

```sh
mysql> create database `laravel-shop`;
Query OK, 1 row affected (0.01 sec)
mysql> show databases;
+--------------------+
| Database           |
+--------------------+
| information_schema |
| bin                |
| c127               |
| laravel-shop       |
| mysql              |
| performance_schema |
| shineyork          |
| sys                |
+--------------------+
8 rows in set (0.00 sec)

```


> 2.在从服务上通过连接主服务器上的数据库，通过mysqldump备份数据到从数据库中

在主服务器上，设置读锁定有效，这个操作为了确保没有数据库操作，以便获得一致性的快照。

```sh
mysql>flush tables with read lock;
```

然后再从服务上进行数据的备份，并同步导入备份数据

```sh
[root@localhost ~]# mysqldump -h192.168.6.14 -u root -p laravel-shop > /home/laravel-shop.sql
Enter password:
[root@localhost ~]# mysql -f -u root -p laravel-shop < /home/laravel-shop.sql
Enter password:
[root@localhost ~]# mysql -u root -p
Enter password:
mysql> use laravel-shop;
Database changed
mysql> show tables;

```

在数据备份完成之后这个时候就可以恢复主数据库的写操作执行命令如下：

```sh
mysql> unlock tables;
```

#### 2.1.2 暴力备份

停止主库，然后复制主库中的data放到从库中

#### 2.1.3 使用mydumper

mydumper是一个针对MySQL和drizzle的高性能多线程的备份和恢复工具。瓷公鸡的开发人员分别来自MySQL，Facebook，skysql公司、目前已经有一些大型产品项目业务测试并使用了该工具。
我们在恢复数据库时也可以使用mydumper。mydumper的主要特性包括：
>采用轻量级C语言写的代码。 
>相比于mysqldump，其速度快了近10倍。
>具有事务性和非事务性表一致的快照（适用于0.2.2+）。
>可快速进行文件压缩（File compression on-the-fly）。
>支持导出binlog。 
>可多线程恢复（适用于0.2.1+）。 
>可以用守护进程的工作方式，定时扫描和输出连续的二进制日志。

按装命令如下所示：

```sh
[root@localhost wwwroot]# yum install glib2-devel zlib-devel pcre-devel cmake
[root@localhost wwwroot]# git clone https://github.com/maxbube/mydumper.git
[root@localhost wwwroot]# cd mydumper
[root@localhost wwwroot]# cmake .
[root@localhost wwwroot]# make
[root@localhost wwwroot]# make install
[root@localhost wwwroot]# mydumper -V
mydumper 0.9.1, built against MySQL 5.7.27
```

Mydumper中的主要参数如下：

· -host，-h：连接的MySQL服务器。 
· -user，-u：用户备份的连接用户。口-password，-p：用户的密码。 
· -port，-P：连接端口。 
· -socket，-S：连接socket文件。口-database，-B：需要备份的数据库。 
· -table-list，-T：需要备份的表，用逗号（，）分隔。 
· -outputdir，-o：输出的目录。 
· -build-empty-files，-e：默认无数据则只有表结构文件。
· -regex，-x：支持正则表达式，如mydumper-regex'（2l（mysqltest）'。 
· -ignore-engines，-i：忽略的存储引擎。 
· -no-schemas，-m：不导出表结构。 
· -long-query-guard：长查询，默认60s。 
· -kill-long-queries，-k：可以设置kill长查询。 
· -verbose，-v：0=silent，1=errors，2=warmings，3=info，默认是2。 
· -binlogs，-b：导出binlog。口-daemon，-D：启用守护进程模式。 
· -snapshot-interval，-I:dump快照间隔时间，默认60s。 
· -logfile，-L:mysaqldumper的目志输出，一般在Daemon模式下使用。

mydumper与mysqldump 备份数据对比

```sh
[root@localhost home]# time mydumper -u root -p root -B laravel-shop -o /home/laravel-shop2.sql

real    0m0.039s
user    0m0.004s
sys    0m0.035s
[root@localhost home]# time mysqldump -u root -p laravel-shop > /home/laravel-shop3.sql
Enter password:

real    0m2.093s
user    0m0.016s
sys      0m0.047s
```

对比mysql与myloader数据还原

```sh
[root@localhost home]# time mysql -f -u root -p laravel-shop < /home/laravel-shop3.sql
Enter password:

real    0m2.511s
user    0m0.017s
sys    0m0.033s
[root@localhost home]# time myloader -u root -p root -B laravel-shop -d /home/laravel-shop3.sql
** (myloader:9506): CRITICAL **: 06:38:43.292: the specified directory is not a mydumper backup

real    0m0.006s
user    0m0.003s
sys    0m0.003s
```

### 2.2 热备份与恢复

xtrabackup手册：https://www.percona.com/doc/percona-xtrabackup/2.4/installation/yum_repo.html

热备份的方式也是直接复制数据物理文件，和冷备份一样，但热备份可以不停机直接复制，一般用于7×24小时不间断的重要核心业务。MySQL社区版的热备份工具ImnoDB Hot Backup是付费的，只能试用30天，只有购买企业版才可以得到永久使用权。Percona公司发布了一个xtrabackup热备份工具，和官方付费版的功能一样，支持在线热备份（备份时不影响数据读写），是商业备份工具InnoDBHot Backup的一个很好的替代品。下面具体介绍一下这个软件的使用方法。

xtrabackup是Percona公司的开源项目，用以实现类似InnoDB官方的热备份工具ImmoDB Hot Backup的功能，它能非常快速地备份与恢复MySQL数据库。xtrabackup中包含两个工具：

>· xtrabackup是用于热备份InnoDB及XtraDB表中数据的工具，不能备份其他类型的表，也不能备份数据表结构。 
>· innobackupex是将xtrabackup进行封装的perl脚本，它提供了备份MyISAM表的能力。由于innobackupex的功能更为全面完善，所以一般选择innobackupex来进行备份。

下面来看看xtrabackup的安装方法，安装命令如下：

```sh
[root@localhost file]$ wget https://www.percona.com/downloads/XtraBackup/Percona-XtraBackup-2.4.4/binary/redhat/7/x86_64/percona-xtrabackup-24-2.4.4-1.el7.x86_64.rpm
[root@localhost file]$ yum localinstall percona-xtrabackup-24-2.4.4-1.el7.x86_64.rpm
[root@localhost file]# rpm -qa | grep xtrabackup
```

常用选项

```sh
   --host     指定主机
   --user     指定用户名
   --password    指定密码
   --port     指定端口
   --databases     指定数据库
   --incremental    创建增量备份
   --incremental-basedir   指定包含完全备份的目录
   --incremental-dir      指定包含增量备份的目录
   --apply-log        对备份进行预处理操作
     一般情况下，在备份完成后，数据尚且不能用于恢复操作，因为备份的数据中可能会包含尚未提交的事务或已经提交但尚未同步至数据文件中的事务。因此，此时数据文件仍处理不一致状态。“准备”的主要作用正是通过回滚未提交的事务及同步已经提交的事务至数据文件也使得数据文件处于一致性状态。
   --redo-only      不回滚未提交事务
   --copy-back     恢复备份目录

```
开始进行备份操作，进入主库中

```sh
[root@centos ~]# innobackupex --defaults-file=/etc/my.cnf --user=root --password=root --backup /home/laravel-shop
[root@localhost home]# ll /home/laravel-shop/2019-09-26_12-43-34/
总用量 75832
-rw-r----- 1 root root      425 9月  26 12:43 backup-my.cnf
drwxr-x--- 2 root root       58 9月  26 12:43 bin
-rw-r----- 1 root root      361 9月  26 12:43 ib_buffer_pool
-rw-r----- 1 root root 77594624 9月  26 12:43 ibdata1
drwxr-x--- 2 root root     4096 9月  26 12:43 laravel@002dshop
drwxr-x--- 2 root root     4096 9月  26 12:43 mysql
drwxr-x--- 2 root root     8192 9月  26 12:43 performance_schema
drwxr-x--- 2 root root     8192 9月  26 12:43 sys
drwxr-x--- 2 root root       46 9月  26 12:43 test
-rw-r----- 1 root root       24 9月  26 12:43 xtrabackup_binlog_info
-rw-r----- 1 root root      113 9月  26 12:43 xtrabackup_checkpoints
-rw-r----- 1 root root      508 9月  26 12:43 xtrabackup_info
-rw-r----- 1 root root     2560 9月  26 12:43 xtrabackup_logfile
[root@localhost home]# scp -r /home/laravel-shop/ root@192.168.153.127:/home/laravel-shop


```
然后呢 进入从库中

```sh
[root@localhost server]# ll /home/laravel-shop/2019-09-26_12-43-34/
总用量 75832
-rw-r----- 1 root root      425 9月  27 21:54 backup-my.cnf
drwxr-x--- 2 root root       58 9月  27 21:54 bin
-rw-r----- 1 root root      361 9月  27 21:54 ib_buffer_pool
-rw-r----- 1 root root 77594624 9月  27 21:54 ibdata1
drwxr-x--- 2 root root     4096 9月  27 21:54 laravel@002dshop
drwxr-x--- 2 root root     4096 9月  27 21:54 mysql
drwxr-x--- 2 root root     8192 9月  27 21:54 performance_schema
drwxr-x--- 2 root root     8192 9月  27 21:54 sys
drwxr-x--- 2 root root       46 9月  27 21:54 test
-rw-r----- 1 root root       24 9月  27 21:54 xtrabackup_binlog_info
-rw-r----- 1 root root      113 9月  27 21:54 xtrabackup_checkpoints
-rw-r----- 1 root root      508 9月  27 21:54 xtrabackup_info
-rw-r----- 1 root root     2560 9月  27 21:54 xtrabackup_logfile
[root@localhost server]#
[root@localhost server]# /etc/init.d/mysqld stop
Shutting down MySQL.. SUCCESS!
[root@localhost server]# mv /www/server/data /www/server/data2
[root@localhost server]# mv /www/server/data /www/server/data2
[root@localhost server]# innobackupex --defaults-file=/etc/my.cnf --copy-back /home/laravel-shop/2019-09-26_12-43-34/
[root@localhost server]# chown -R mysql:mysql /www/server/data
[root@localhost server]# /etc/init.d/mysqld start
Starting MySQL.Logging to '/www/server/data/localhost.localdomain.err'.
. SUCCESS!
[root@localhost server]# mysql -u root -p
mysql> show databases;
+--------------------+
| Database           |
+--------------------+
| information_schema |
| bin                |
| laravel-shop       |
| mysql              |
| performance_schema |
| sys                |
| test               |
+--------------------+
7 rows in set (0.02 sec
```

对于热备份实现解释

1.innobackupex启动后，会先fork一个进程，用于启动xtrabackup,然后等待xtrabackup备份ibd数据文件；
2.xtrabackup在备份INNODB数据时，有2中线程：redo拷贝线程和ibd数据拷贝线程。xtrabackup进程开始执行后，会启动一个redo拷贝的线程，用于从最新的checkpoint点开始顺序拷贝redo.log；再启动ibd数据拷贝线程，进行拷贝ibd数据。这里是先	启动redo拷贝线程的。在此阶段，innobackupex进行处于等待状态（等待文件被创建）
3.xtrabackup拷贝完成ibd数据文件后，会通知innobackupex（通过创建文件），同时xtrabackup进入等待状态（redo线程依旧在拷贝redo.log）
4.innobackupex收到xtrabackup通知后，执行flush tables with read lock(ftwrl),取得一致性位点，然后开始备份非innodb文件（如frm，myd，myi，csv，opt,par等格式的文件），在拷贝非Innodb文件的过程当中，数据库处于全局只读状态。
5.当innobackup拷贝完所有的非Innodb文件后，会通知XtraBackup，通知完成后，进入等待状态；
6.xtrabackup收到innobackupex备份完成的通知后，会停止redo拷贝线程，然后通知innoupex，redo.文件拷贝完成；
7.innobackupex收到redo.log备份完成后，就进行解锁操作，执行：unlock tables；
8.最后innobackupex和xtrabackup进程鸽子释放资源，写备份元数据信息等，innobackupex等xtrabackup子进程结束后退出。

























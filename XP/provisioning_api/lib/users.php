<?php

/**
 * ownCloud
 *
 * @copyright (C) 2014 ownCloud, Inc.
 *
 * @author Tom <tom@owncloud.com>
 * @author Thomas Müller <deepdiver@owncloud.com>
 * @author Bart Visscher
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU AFFERO GENERAL PUBLIC LICENSE
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU AFFERO GENERAL PUBLIC LICENSE for more details.
 *
 * You should have received a copy of the GNU Affero General Public
 * License along with this library.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

namespace OCA\Provisioning_API;

use \OC_OCS_Result;
use \OC_SubAdmin;
use \OC_User;
use \OC_Group;
use \OC_Helper;

class Users {

	/**
	 * returns a list of users
	 */
/*
test en ligne de commande
login="admin"
pass=""
url="http://owncloud-dev.umrthema.univ-fcomte.fr/owncloud"
curl -v -u "$login:$pass" -XGET "$url/ocs/v1.php/cloud/users"
*/
	public static function getUsers(){
		return new OC_OCS_Result();
	}


	public static function getUser($parameters){
		$userId = $parameters['userid'];
		return new OC_OCS_Result();
	}



}

#ifndef BLE_DEFINED_H_
#define BLE_DEFINED_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

extern uint8_t packet_event_type;
extern bool ble_heartbeat_on;
extern bool ble_notification_enabled;

uint16_t PeripheralReadData(uint16_t att_handle, uint8_t **data);

void BLE_set_heartbeat_period_ms(uint16_t period_ms);
int BLE_init(const uint8_t *profile);
void BLE_hci_power_on(void);

void BLE_advertise(uint8_t *adv_data, uint8_t adv_data_len);
void BLE_notify(uint16_t att_handle);
void BLE_gap_local_bd_addr(uint8_t *local_addr);

void BLE_request_can_send_now_event(void);
void BLE_cyw43_arch_gpio_put(uint8_t pin, uint8_t value);

#ifdef __cplusplus
}
#endif

#endif /* BLE_DEFINED_H_ */

